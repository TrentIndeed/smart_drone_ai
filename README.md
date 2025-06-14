# smart_drone_ai
    Smart hunter AI drone that tracks down a target running away from obstacles.

    Prints thinking during program execution. 
    Implements an interative prompting mechanism and a skill library similar to the minecraft voyager.

How It Works:

    Drone and target move on a grid.
    Uses a locally running LLaMA model via ollama run llama3.
    Prompts LLaMA with the environment and available skills.
    LLaMA chooses the next move and reasoning, which is printed live.

    Target moves randomly, loop continues for a set amount of time.

How to run:
    Download llama 3, run Python3 main.py

🧠 Features:
    Embeds a simple “skill library” like Voyager (intercept, predict path, etc.).
    Supports interactive prompting and live reasoning display.
    Easily extensible for:
    Dynamic environments
    More sophisticated skills
    Memory / learned skill accumulation

Future:
    The goal is for the drone to start with background knowledge (strategies, tools, agile skills).
    LLM chooses subgoals, creates code snippets to act, and learns over time what works best.

    🧠 Why it’s relevant: The LLM plans high-level goals, learns skills, and adapts strategies across tasks.