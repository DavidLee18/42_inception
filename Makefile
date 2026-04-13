NAME    = inception

all: $(NAME)

$(NAME):
	docker compose -f srcs/docker-compose.yml --build --no-cache
	docker compose -f srcs/docker-compose.yml up -d

down:
	docker compose -f srcs/docker-compose.yml down

fclean: down
	docker compose -f srcs/docker-compose.yml down --volumes --rmi all --remove-orphans
	docker image prune -af

re: fclean all

.PHONY: all down fclean re
