# SSH passphrase prompts -> promptd windows (matches environment.d so
# interactive shells behave the same as systemd-spawned processes).
export SSH_ASKPASS=/home/tinoy/.local/bin/ssh-askpass-promptd
export SSH_ASKPASS_REQUIRE=force

# Proton Pass vault session -> durable local key store (matches environment.d so
# interactive shells behave the same as systemd-spawned processes). The default
# kernel keyring is cleared at reboot, after which pass-cli finds its own session
# data with no key and forces a logout.
export PROTON_PASS_KEY_PROVIDER=fs

# Subagent launch wrapper: it marks a pi process as a subagent (PI_SUBAGENT=1)
# so the canon extension scopes injected lines by audience. pi-subagents uses
# this binary for its Herdr project panes and the profile model probe; subagent
# children run as in-process sessions and do not spawn it.
export PI_SUBAGENT_PI_BINARY=/home/tinoy/.local/bin/pi-subagent

# Extended provider prompt-cache retention (OpenAI-compatible: up to 24h).
export PI_CACHE_RETENTION=long

# The sudo-approve package resolves the promptd router from this path; the package
# ships no home-directory default, so an unset value refuses the approval route.
export SUDO_APPROVE_ROUTE=/home/tinoy/.local/bin/tinshell-route
