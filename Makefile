NAME    = inception

all: $(NAME)

$(NAME):
	cd srcs && docker compose up -d --build

down:
	cd srcs && docker compose -f down

fclean: down
	cd srcs && docker compose -f down --volumes --rmi all --remove-orphans && docker image prune -af

re: fclean all

.PHONY: all down fclean re
