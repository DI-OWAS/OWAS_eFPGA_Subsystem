REPO_ROOT := $(abspath ..)
NIX_DIR ?= $(REPO_ROOT)/OWAS_Fabric/FABulous

.PHONY: all act_bank_container psum_requant_container efpga_subsystem_top gzip gunzip nix help

all: act_bank_container psum_requant_container efpga_subsystem_top

help:
	@echo "Targets in librelane/ (run them inside make nix):"
	@echo "  all (default)           act_bank_container, psum_requant_container, then efpga_subsystem_top"
	@echo "  act_bank_container      flow of one macro; make -C <macro> help lists its targets"
	@echo "  psum_requant_container"
	@echo "  efpga_subsystem_top"
	@echo "  gzip                    gzip the large top views"
	@echo "  gunzip                  unpack every *.gz under MACROS/ (keeps the .gz)"
	@echo "  nix                     shell in the FABulous nix env"

act_bank_container:
	$(MAKE) -C act_bank_container

psum_requant_container:
	$(MAKE) -C psum_requant_container

efpga_subsystem_top:
	$(MAKE) -C efpga_subsystem_top

gzip:
	$(MAKE) -C efpga_subsystem_top gzip

gunzip:
	find "$(REPO_ROOT)/MACROS" -name "*.gz" -exec sh -c '\
		set -eu; \
		for z do \
			gzip -dkf "$$z"; \
			printf "Extracted %s\n" "$$z"; \
		done' sh {} +

nix:
	@test -f "$(NIX_DIR)/flake.nix" \
		|| { echo "ERROR: $(NIX_DIR) has no flake.nix: run git submodule update --init --recursive"; exit 1; }
	nix develop $(NIX_DIR) --command bash -c 'cd "$(CURDIR)" && exec bash --rcfile <(cat "$${HOME}/.bashrc"; printf "%s\n" '\''PS1="\[\\033[01;35m\][nix-shell]\[\\033[00m\] \[\\033[01;32m\]$${USER}@\\h\[\\033[00m\]:\[\\033[01;34m\]\\w\[\\033[00m\]> "'\'') -i'

