NAME    = inception

all: $(NAME)

$(NAME):
	mkdir -p /home/jaehylee/data/db /home/jaehylee/data/wp
	docker compose -f srcs/docker-compose.yml build --no-cache
	docker compose -f srcs/docker-compose.yml up -d

down:
	docker compose -f srcs/docker-compose.yml down

fclean: down
	docker compose -f srcs/docker-compose.yml down --volumes --rmi all --remove-orphans
	docker image prune -af
	rm -rf /home/jaehylee/data/db
	rm -rf /home/jaehylee/data/wp

re: fclean all

.PHONY: all down fclean re
