all:
	cd srcs && docker compose up -d --build

clean:
	cd srcs && docker compose down --volumes --rmi all --remove-orphans
