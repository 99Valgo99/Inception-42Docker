all: up

up:
	docker compose -f srcs/docker-compose.yml up --build

down:
	docker compose -f srcs/docker-compose.yml down

clean: down

fclean: clean
	docker system prune -af

re: fclean up

.PHONY: all up down clean fclean re