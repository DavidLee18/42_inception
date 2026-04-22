NAME      = inception
COMPOSE   = docker compose -f srcs/docker-compose.yml
DATA_DIR  = /home/jaehylee/data
VM_DEST   = /home/vagrant/inception

# ═════════════════════════════════════════════════════════════════
# Docker stack — run these INSIDE the VM
# ═════════════════════════════════════════════════════════════════

.PHONY: all down fclean re

all: $(NAME)

$(NAME):
	mkdir -p $(DATA_DIR)/db $(DATA_DIR)/wp
	$(COMPOSE) build --no-cache
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

fclean: down
	$(COMPOSE) down --volumes --rmi all --remove-orphans

re: fclean all

# ═════════════════════════════════════════════════════════════════
# VM management — run these on the HOST (42 cluster machine)
# ═════════════════════════════════════════════════════════════════

.PHONY: vm vm-ssh vm-sync vm-destroy

# (1) Bring the VM up (idempotent — skipped if already running).
vm:
	vagrant up

# (2) SSH into the VM.
vm-ssh:
	@vagrant ssh

# (3) Snapshot copy of the local repo into the VM at $(VM_DEST).
#     This is a SNAPSHOT, not a live mount. For the live mount,
#     use /vagrant inside the VM (Vagrant's default synced folder).
vm-sync:
	@vagrant status --machine-readable | grep -q ',state,running$$' \
	    || { echo "✗ VM is not running. Run 'make vm' first."; exit 1; }
	@echo "▶ Copying repo → VM:$(VM_DEST) (excl. .git .vagrant *.swp)"
	@vagrant ssh -c "rm -rf $(VM_DEST) && mkdir -p $(VM_DEST)" >/dev/null
	@tar c \
	    --exclude='.git' \
	    --exclude='.vagrant' \
	    --exclude='*.swp' \
	    -f - . \
	  | vagrant ssh -c "tar xf - -C $(VM_DEST)" >/dev/null
	@echo "✔ Done. Snapshot now at $(VM_DEST) inside the VM."

vm-destroy:
	@vagrant destroy -f
