.PHONY: help install app hooks demo crowd run uninstall clean

help: ## Show these commands
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-10s %s\n", $$1, $$2}'

install: ## Build PitCrew.app, put it in Applications, launch it, and hook up Claude Code
	./scripts/build-app.sh --install
	./scripts/install-hooks.sh

app: ## Build build/PitCrew.app only
	./scripts/build-app.sh

hooks: ## Register Pit Crew's hooks with Claude Code (~/.claude/settings.json)
	./scripts/install-hooks.sh

demo: ## Guided tour with fake agents (Pit Crew must be running)
	./scripts/demo.py

crowd: ## Stress test: 50 fake agents with subagents and prompts (N=72 make crowd for more)
	./scripts/demo.py --crowd $(or $(N),50)

run: ## Run from source without building the app
	swift run

uninstall: ## Remove the app, the hooks and ~/.pitcrew
	./scripts/uninstall.sh

clean: ## Delete build output
	rm -rf .build build
