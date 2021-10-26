#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# This file is part of solidity.
#
# solidity is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# solidity is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with solidity.  If not, see <http://www.gnu.org/licenses/>
#
# (c) 2019 solidity contributors.
#------------------------------------------------------------------------------

set -e

source scripts/common.sh
source test/externalTests/common.sh

verify_input "$@"
BINARY_TYPE="$1"
BINARY_PATH="$2"

function compile_fn { npm run build; }
function test_fn { npm test; }

function gnosis_safe_test
{
    local repo="https://github.com/gnosis/safe-contracts.git"
    local branch=main
    local config_file="hardhat.config.ts"
    local config_var=userConfig

    local compile_only_presets=(
        ir-optimize-evm+yul        # Compiles but tests fail. See https://github.com/nomiclabs/hardhat/issues/2115
    )
    local settings_presets=(
        "${compile_only_presets[@]}"
        #ir-no-optimize            # "YulException: Variable var_call_430_mpos is 1 slot(s) too deep inside the stack."
        #ir-optimize-evm-only      # "YulException: Variable var_module_1480 is 9 slot(s) too deep inside the stack."
        legacy-no-optimize
        legacy-optimize-evm-only
        legacy-optimize-evm+yul
    )

    local selected_optimizer_presets
    selected_optimizer_presets=$(circleci_select_steps_multiarg "${settings_presets[@]}")
    print_optimizer_presets_or_exit "$selected_optimizer_presets"

    setup_solc "$DIR" "$BINARY_TYPE" "$BINARY_PATH"
    download_project "$repo" "$branch" "$DIR"
    [[ $BINARY_TYPE == native ]] && replace_global_solc "$BINARY_PATH"

    # NOTE: The patterns below intentionally have hard-coded versions.
    # When the upstream updates them, there's a chance we can just remove the regex.
    sed -i 's|"@gnosis\.pm/mock-contract": "\^4\.0\.0"|"@gnosis.pm/mock-contract": "github:solidity-external-tests/mock-contract#master_080"|g' package.json
    sed -i 's|"@openzeppelin/contracts": "\^3\.4\.0"|"@openzeppelin/contracts": "^4.0.0"|g' package.json

    # Disable two tests failing due to Hardhat's heuristics not yet updated to handle solc 0.8.10.
    # TODO: Remove this when Hardhat implements them (https://github.com/nomiclabs/hardhat/issues/2051).
    sed -i "s|\(it\)\(('should revert if called directly', async () => {\)|\1.skip\2|g" test/handlers/CompatibilityFallbackHandler.spec.ts

    neutralize_package_lock
    neutralize_package_json_hooks
    force_hardhat_compiler_binary "$config_file" "$BINARY_TYPE" "$BINARY_PATH"
    force_hardhat_compiler_settings "$config_file" "$(first_word "$selected_optimizer_presets")" "$config_var"
    npm install

    replace_version_pragmas
    [[ $BINARY_TYPE == solcjs ]] && force_solc_modules "${DIR}/solc"

    replace_version_pragmas

    for preset in $selected_optimizer_presets; do
        hardhat_run_test "$config_file" "$preset" "${compile_only_presets[*]}" compile_fn test_fn "$config_var"
    done
}

external_test Gnosis-Safe gnosis_safe_test
