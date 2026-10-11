terraform {
  required_version = ">= 1.5.0"
}

# Аналог сети, в которой находятся backend-серверы и балансировщик
resource "terraform_data" "network" {
  input = {
    name = "sflt-hw4-network"
  }

  provisioner "local-exec" {
    command = <<-EOT
      docker network inspect ${self.input.name} >/dev/null 2>&1 || \
      docker network create ${self.input.name}
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "docker network rm ${self.input.name} >/dev/null 2>&1 || true"
  }
}

# Два одинаковых backend-сервера.
# Ключевое требование ДЗ: создаются через count = 2.
resource "terraform_data" "web" {
  count = 2

  input = {
    name = "web-${count.index + 1}"
  }

  depends_on = [
    terraform_data.network
  ]

  provisioner "local-exec" {
    command = <<-EOT
      docker rm -f ${self.input.name} >/dev/null 2>&1 || true
      docker pull nginx:alpine
      docker run -d \
        --name ${self.input.name} \
        --network sflt-hw4-network \
        --restart unless-stopped \
        nginx:alpine
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "docker rm -f ${self.input.name} >/dev/null 2>&1 || true"
  }
}

# Аналог Network Load Balancer
resource "terraform_data" "load_balancer" {
  input = {
    name        = "network-load-balancer"
    config_hash = filesha256("${path.module}/haproxy.cfg")
  }

  depends_on = [
    terraform_data.web
  ]

  provisioner "local-exec" {
    command = <<-EOT
      docker rm -f network-load-balancer >/dev/null 2>&1 || true
      docker pull haproxy:alpine
      docker run -d \
        --name network-load-balancer \
        --network sflt-hw4-network \
        --restart unless-stopped \
        -p 80:80 \
        -p 8404:8404 \
        -v "${path.module}/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro" \
        haproxy:alpine
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "docker rm -f network-load-balancer >/dev/null 2>&1 || true"
  }
}

output "backend_servers" {
  value = [
    for server in terraform_data.web : server.input.name
  ]
}

output "load_balancer_url" {
  value = "http://200.169.181.246"
}

output "health_status_url" {
  value = "http://200.169.181.246:8404/stats"
}
