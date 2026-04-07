NAME    = inception

all: $(NAME)

$(NAME):
	cd srcs && docker compose up -d --build

clean:
	docker compose -f down

fclean: clean
	cd srcs && docker compose -f down --volumes --rmi all --remove-orphans
	docker image prune -af

re: fclean all

.PHONY: all clean fclean re
