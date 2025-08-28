# ✨ Features

📦 Patrolbag item with its own stash (configurable slots & weight)

🧑‍✈️ NPC interaction via ox_target (take, open, return bag)

# 🔒 Security checks

Anti-spam (cooldowns & rate limits)

Whitelist job restriction (e.g. police)

Prevents “bag-in-bag” exploits

Enforces one bag per player

⚡ Performance optimized with caching, status checker, and memory limits

🛠️ Config-driven

NPC model & location

Seed items on first open

Notifications handled server-side

Adjustable performance & security settings

# 🔄 Automatic state sync when players join

🧹 Maintenance thread for cleanup of cache, cooldowns, and limits

# 📂 Requirements

ox_lib

ox_inventory

ox_target

es_extended

 #⚙️ Installation

Download the resource and place it in your resources folder

Add to your server.cfg:

ensure cmd_patrolbag


Configure config.lua to your needs (jobs, NPC position, items, limits, etc.)

# 📜 Usage

Interact with the NPC to:

Take a patrolbag

Open your patrolbag

Return the patrolbag
