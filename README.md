## USE THE RELEASE FOR THE QB/QBOX VERSION. AND I updated the resource to have locales option. to use english, german and swedish. 

# Patrol Bag (QBCore/QBOX Version)

This is a modified version of the original [cmd_patrolbag](https://github.com/cmdscripts/cmd_patrolbag)
by [cmdscripts](https://github.com/cmdscripts)
Original project licensed under the [Apache License 2.0](LICENSE).
Modifications made by `themiruvo`, 2025.


## [Preview](https://streamable.com/eknoax)
## [Support](https://discord.gg/Evd7gvpTyW)
# ✨ Features

📦 Patrolbag item with its own stash (configurable slots & weight)

🧑‍✈️ NPC interaction via ox_target (take, open, return bag)

# 🔒 Security checks

Anti-spam (cooldowns & rate limits)

Whitelist job restriction (e.g. police)

Prevents “bag-in-bag” exploits

Enforces one bag per player

⚡ Performance optimized with caching, status checker, and memory limits

# 🛠️ Config-driven

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

~~es_extended~~ it supports now qb/qbox

 # ⚙️ Installation

Download the resource and place it in your resources folder

Add to your server.cfg:

ensure cmd_patrolbag


Configure config.lua to your needs (jobs, NPC position, items, limits, etc.)

# 📜 Usage

Interact with the NPC to:

Take a patrolbag

Open your patrolbag

Return the patrolbag
