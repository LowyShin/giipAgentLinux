#!/bin/bash
# Simulation of giipAgent3.sh config loading logic

# 1. Create dummy parent config
echo 'sk="PARENT_SECRET_KEY"' > ../giipAgent.cnf

# 2. Create dummy local template (trap)
echo 'sk="TEMPLATE_KEY"' > ./giipAgent.cnf

# 3. Define load_config exactly as in lib/common.sh
load_config() {
	local config_file="${1:-../giipAgent.cnf}"
	
	if [ ! -f "$config_file" ]; then
		echo "❌ Error: Configuration file not found: $config_file"
		return 1
	fi
	
	. "$config_file"
}

# 4. Simulate giipAgent3.sh call (no arguments)
load_config

# 5. Verify which key was loaded
if [ "$sk" == "PARENT_SECRET_KEY" ]; then
    echo "✅ SUCCESS: Loaded PARENT config correctly."
    echo "Loaded SK: $sk"
    exit 0
elif [ "$sk" == "TEMPLATE_KEY" ]; then
    echo "❌ FAILURE: Loaded TEMPLATE config (Dangerous!)."
    echo "Loaded SK: $sk"
    exit 1
else
    echo "❌ FAILURE: Failed to load any config."
    exit 1
fi
