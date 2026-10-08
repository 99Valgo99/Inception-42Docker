LOGIN := ayel-bou
DATA_DIR := /home/$(LOGIN)/data

all: up

up: $(DATA_DIR)/mariadb $(DATA_DIR)/wordpress
	docker compose -f srcs/docker-compose.yml up --build

$(DATA_DIR)/mariadb:
	sudo mkdir -p $(DATA_DIR)/mariadb

$(DATA_DIR)/wordpress:
	sudo mkdir -p $(DATA_DIR)/wordpress

down:
	docker compose -f srcs/docker-compose.yml down

clean: down

fclean: clean
	docker system prune -af
	sudo rm -rf $(DATA_DIR)/mariadb
	sudo rm -rf $(DATA_DIR)/wordpress

re: fclean up

.PHONY: all up down clean fclean re