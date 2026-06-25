# Variables
COMPOSE_FILE = srcs/docker-compose.yml
DATA_DIR = /home/jow/data

.PHONY: all build up down clean fclean re setup

all: build up

# Create the host directories that the named volumes bind to.
# These MUST exist before `up`, otherwise the bind mount fails with
# "no such file or directory" (e.g. after fclean removes them).
setup:
	mkdir -p $(DATA_DIR)/mariadb $(DATA_DIR)/wordpress

# Build images
build:
	docker compose -f $(COMPOSE_FILE) build

# Start services
up: setup
	docker compose -f $(COMPOSE_FILE) up -d

# Stop services
down:
	docker compose -f $(COMPOSE_FILE) down

# Clean containers and images
clean:
	docker compose -f $(COMPOSE_FILE) down
	docker system prune -af

# Full clean including named volumes
fclean:
	docker compose -f $(COMPOSE_FILE) down -v
	docker system prune -af
	docker volume prune -f
	sudo rm -rf $(DATA_DIR)

# Rebuild everything
re: fclean all
