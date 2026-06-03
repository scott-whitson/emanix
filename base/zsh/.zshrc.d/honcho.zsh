# base/zsh/.zshrc.d/honcho.zsh — shared Honcho client env for datacore + Debian workstations.

export HONCHO_ENABLED="${HONCHO_ENABLED:-true}"
export HONCHO_URL="${HONCHO_URL:-http://datacore.scottwhitson.ts.net:8008}"
export HONCHO_WORKSPACE="${HONCHO_WORKSPACE:-pi}"
export HONCHO_POLICY="${HONCHO_POLICY:-query before answer when personalized memory helps; write only curated durable facts, decisions, and preferences}"
