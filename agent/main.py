"""
Main LangGraph Agent Loop for Hunter Drone AI
Coordinates the entire hunter-drone system using LangGraph state management
"""

import asyncio
import json
import time
from typing import Dict, List, TypedDict, Annotated
from datetime import datetime
import logging

from langgraph.graph import StateGraph, END
from langgraph.checkpoint.memory import MemorySaver
from langchain_core.messages import HumanMessage, AIMessage

from memory_store import MemoryStore
from planner import DronePlanner
from evaluator import PerformanceEvaluator

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class AgentState(TypedDict):
    """State maintained by the LangGraph agent"""
    messages: Annotated[List[dict], "Communication with Godot"]
    drone_position: List[float]
    target_position: List[float]
    obstacles: List[List[float]]
    current_plan: List[List[float]]
    plan_step: int
    reasoning: str
    performance_metrics: Dict
    memory_context: Dict
    emergency_mode: bool
    last_update_time: float

class HunterDroneAgent:
    """Main LangGraph agent for coordinating drone hunting behavior"""
    
    def __init__(self, grid_size: int = 10):
        self.grid_size = grid_size
        self.memory_store = MemoryStore()
        self.planner = DronePlanner(grid_size)
        self.evaluator = PerformanceEvaluator()
        
        # Initialize LangGraph
        self.graph = self._create_graph()
        self.memory = MemorySaver()
        self.app = self.graph.compile(checkpointer=self.memory)
        
        # Communication with Godot
        self.running = True
        self.last_decision_time = 0
        self.decision_interval = 0.5  # 500ms between decisions
        
    def _create_graph(self) -> StateGraph:
        """Create the LangGraph state machine"""
        graph = StateGraph(AgentState)
        
        # Add nodes
        graph.add_node("perceive", self._perceive_environment)
        graph.add_node("remember", self._recall_memories)
        graph.add_node("plan", self._generate_plan)
        graph.add_node("evaluate", self._evaluate_performance)
        graph.add_node("act", self._execute_action)
        
        # Define edges
        graph.add_edge("perceive", "remember")
        graph.add_edge("remember", "plan")
        graph.add_edge("plan", "evaluate")
        graph.add_edge("evaluate", "act")
        graph.add_edge("act", END)
        
        # Set entry point
        graph.set_entry_point("perceive")
        
        return graph
    
    async def _perceive_environment(self, state: AgentState) -> AgentState:
        """Process incoming environment data from Godot"""
        logger.info(f"Perceiving environment: Drone at {state['drone_position']}, Target at {state['target_position']}")
        
        # Update timing
        state["last_update_time"] = time.time()
        
        # Calculate distances and basic metrics
        drone_pos = state["drone_position"]
        target_pos = state["target_position"]
        distance_to_target = ((drone_pos[0] - target_pos[0])**2 + (drone_pos[1] - target_pos[1])**2)**0.5
        
        # Update performance metrics
        state["performance_metrics"] = {
            "distance_to_target": distance_to_target,
            "timestamp": time.time(),
            "emergency_mode": state.get("emergency_mode", False)
        }
        
        return state
    
    async def _recall_memories(self, state: AgentState) -> AgentState:
        """Retrieve relevant memories and context"""
        # Get relevant memories based on current situation
        memory_context = self.memory_store.get_relevant_memories(
            drone_pos=state["drone_position"],
            target_pos=state["target_position"],
            obstacles=state["obstacles"]
        )
        
        state["memory_context"] = memory_context
        logger.info(f"Retrieved {len(memory_context)} relevant memories")
        
        return state
    
    async def _generate_plan(self, state: AgentState) -> AgentState:
        """Generate movement plan using the planner"""
        try:
            plan, reasoning = await self.planner.create_interception_plan(
                drone_pos=state["drone_position"],
                target_pos=state["target_position"],
                obstacles=state["obstacles"],
                memory_context=state["memory_context"],
                emergency_mode=state.get("emergency_mode", False)
            )
            
            state["current_plan"] = plan
            state["reasoning"] = reasoning
            state["plan_step"] = 0
            
            logger.info(f"Generated plan with {len(plan)} steps: {reasoning[:100]}...")
            
        except Exception as e:
            logger.error(f"Planning failed: {e}")
            # Fallback to simple direct movement
            state["current_plan"] = [state["target_position"]]
            state["reasoning"] = f"Fallback plan due to error: {str(e)}"
            state["plan_step"] = 0
        
        return state
    
    async def _evaluate_performance(self, state: AgentState) -> AgentState:
        """Evaluate current performance and adjust strategy"""
        evaluation = self.evaluator.evaluate_current_state(
            drone_pos=state["drone_position"],
            target_pos=state["target_position"],
            current_plan=state["current_plan"],
            plan_step=state["plan_step"],
            reasoning=state["reasoning"]
        )
        
        # Update emergency mode based on evaluation
        if evaluation.get("stuck", False) or evaluation.get("inefficient", False):
            state["emergency_mode"] = True
            logger.warning("Entering emergency mode due to performance evaluation")
        elif evaluation.get("performing_well", False):
            state["emergency_mode"] = False
        
        # Store evaluation in memory
        self.memory_store.store_evaluation(evaluation)
        
        return state
    
    async def _execute_action(self, state: AgentState) -> AgentState:
        """Execute the planned action"""
        if not state["current_plan"]:
            return state
        
        current_step = state["plan_step"]
        if current_step < len(state["current_plan"]):
            next_position = state["current_plan"][current_step]
            
            # Create message for Godot
            action_message = {
                "type": "move_command",
                "target_position": next_position,
                "reasoning": state["reasoning"],
                "emergency_mode": state.get("emergency_mode", False),
                "timestamp": time.time()
            }
            
            state["messages"].append(action_message)
            logger.info(f"Executing move to {next_position}")
        
        return state
    
    async def process_update(self, drone_pos: List[float], target_pos: List[float], 
                           obstacles: List[List[float]]) -> Dict:
        """Process a single update from Godot"""
        # Check if enough time has passed for a new decision
        current_time = time.time()
        if current_time - self.last_decision_time < self.decision_interval:
            return {"type": "no_action", "reasoning": "Too soon for new decision"}
        
        # Initialize state for this update
        initial_state = {
            "messages": [],
            "drone_position": drone_pos,
            "target_position": target_pos,
            "obstacles": obstacles,
            "current_plan": [],
            "plan_step": 0,
            "reasoning": "",
            "performance_metrics": {},
            "memory_context": {},
            "emergency_mode": False,
            "last_update_time": current_time
        }
        
        # Run the graph
        config = {"configurable": {"thread_id": "hunter_drone_session"}}
        result = await self.app.ainvoke(initial_state, config)
        
        self.last_decision_time = current_time
        
        # Return the last message (action) if any
        if result["messages"]:
            return result["messages"][-1]
        else:
            return {"type": "no_action", "reasoning": "No action generated"}
    
    def stop(self):
        """Stop the agent"""
        self.running = False
        logger.info("Hunter Drone Agent stopped")

async def main():
    """Main entry point for testing the agent"""
    agent = HunterDroneAgent()
    
    # Simulate some updates
    test_updates = [
        ([2.0, 2.0], [8.0, 8.0], [[5.0, 5.0], [3.0, 7.0]]),
        ([2.5, 2.5], [7.5, 8.5], [[5.0, 5.0], [3.0, 7.0]]),
        ([3.0, 3.0], [7.0, 9.0], [[5.0, 5.0], [3.0, 7.0]]),
    ]
    
    for i, (drone_pos, target_pos, obstacles) in enumerate(test_updates):
        print(f"\n--- Update {i+1} ---")
        result = await agent.process_update(drone_pos, target_pos, obstacles)
        print(f"Result: {result}")
        await asyncio.sleep(0.6)  # Wait between updates
    
    agent.stop()

if __name__ == "__main__":
    asyncio.run(main()) 