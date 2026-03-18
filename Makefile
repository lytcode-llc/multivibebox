REPO_DIR := $(shell pwd)
INSTALL_DIR ?= /usr/local/bin

.PHONY: install build uninstall update

install:
	@bash scripts/install.sh

build:
	docker compose build

uninstall:
	@echo "Removing mvb from $(INSTALL_DIR)..."
	@if [ -w "$(INSTALL_DIR)" ]; then \
		rm -f "$(INSTALL_DIR)/mvb"; \
	else \
		sudo rm -f "$(INSTALL_DIR)/mvb"; \
	fi
	@echo "Remove ~/.mvb/ as well? [y/N]" && read ans && \
		if [ "$$ans" = "y" ] || [ "$$ans" = "Y" ]; then \
			rm -rf "$$HOME/.mvb"; \
			echo "Removed ~/.mvb/"; \
		fi
	@echo "Done."

update:
	git pull
	$(MAKE) build
	@echo "Updated. Restart any running sessions with: mvb stop && mvb start"
