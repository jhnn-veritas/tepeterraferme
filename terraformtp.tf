# ==========================================
# 1. LA FONDATION RÉSEAU (Inchangée)
# ==========================================
resource "aws_vpc" "mon_vpc_tp" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true 
  tags = { Name = "mon-vpc-cesi" }
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.mon_vpc_tp.id
  cidr_block              = var.public_subnet_1_cidr
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = { Name = "Subnet-Public-1-AZa" }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.mon_vpc_tp.id
  cidr_block              = var.public_subnet_2_cidr
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = { Name = "Subnet-Public-2-AZb" }
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.mon_vpc_tp.id
  cidr_block        = var.private_subnet_1_cidr
  availability_zone = "us-east-1a"
  tags = { Name = "Subnet-Prive-1-AZa" }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.mon_vpc_tp.id
  cidr_block        = var.private_subnet_2_cidr
  availability_zone = "us-east-1b"
  tags = { Name = "Subnet-Prive-2-AZb" }
}

resource "aws_internet_gateway" "mon_igw" {
  vpc_id = aws_vpc.mon_vpc_tp.id
  tags   = { Name = "mon-igw" }
}

resource "aws_eip" "nat_ip" {
  domain = "vpc"
  tags   = { Name = "IP-NAT-GW" }
}

resource "aws_nat_gateway" "ma_nat_gw" {
  allocation_id = aws_eip.nat_ip.id
  subnet_id     = aws_subnet.public_1.id
  tags = { Name = "ma-nat-gw" }
  depends_on = [aws_internet_gateway.mon_igw]
}

resource "aws_route_table" "rt_publique" {
  vpc_id = aws_vpc.mon_vpc_tp.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mon_igw.id
  }
  tags = { Name = "Table-Routage-Publique" }
}

resource "aws_route_table_association" "pub_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.rt_publique.id
}
resource "aws_route_table_association" "pub_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.rt_publique.id
}

resource "aws_route_table" "rt_privee" {
  vpc_id = aws_vpc.mon_vpc_tp.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ma_nat_gw.id
  }
  tags = { Name = "Table-Routage-Privee" }
}

resource "aws_route_table_association" "priv_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.rt_privee.id
}
resource "aws_route_table_association" "priv_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.rt_privee.id
}

# ==========================================
# 2. LES PARE-FEUX (SECURITY GROUPS)
# ==========================================

# Pare-feu du Load Balancer (Ouvert sur Internet)
resource "aws_security_group" "sg_alb" {
  name        = "johann-sg-alb"
  vpc_id      = aws_vpc.mon_vpc_tp.id 
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "SG-LoadBalancer" }
}

# Pare-feu des Serveurs Web (Restreint au Load Balancer)
resource "aws_security_group" "sg_web" {
  name        = "johann-sg-web-prive"
  vpc_id      = aws_vpc.mon_vpc_tp.id 
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "SG-Serveurs-Prives" }
}

# NOUVEAU : Pare-feu de la Base de Données !
resource "aws_security_group" "sg_db" {
  name        = "johann-sg-db"
  description = "Autorise uniquement les serveurs Web a parler a la DB"
  vpc_id      = aws_vpc.mon_vpc_tp.id 

  ingress {
    from_port       = 3306 # Le port par défaut de MySQL
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_web.id] # Uniquement nos serveurs !
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "SG-Base-De-Donnees" }
}

# ==========================================
# 3. LA BASE DE DONNÉES (AMAZON RDS)
# ==========================================

# On crée un groupe pour dire à RDS d'utiliser nos sous-réseaux privés
resource "aws_db_subnet_group" "mon_groupe_db" {
  name       = "johann-db-subnet-group"
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]
  tags       = { Name = "Mon-Groupe-Subnet-DB" }
}

# La Base de données MySQL en elle-même
resource "aws_db_instance" "ma_bdd" {
  allocated_storage      = 20
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  db_name                = "forumdb"
  username               = "admin"
  password               = "CesiPassword2026!" # Mot de passe (pour le TP)
  parameter_group_name   = "default.mysql8.0"
  db_subnet_group_name   = aws_db_subnet_group.mon_groupe_db.name
  vpc_security_group_ids = [aws_security_group.sg_db.id]
  skip_final_snapshot    = true # Important pour pouvoir détruire le TP facilement
  
  tags = { Name = "Base-De-Donnees-Vichan" }
}

# ==========================================
# 4. LES SERVEURS WEB (PHP + MYSQL)
# ==========================================
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
}

# --- SERVEUR 1 ---
resource "aws_instance" "serveur_1" {
  ami                         = data.aws_ami.amazon_linux_2023.id 
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.private_1.id
  vpc_security_group_ids      = [aws_security_group.sg_web.id]
  associate_public_ip_address = false 
  user_data_replace_on_change = true
  
  # On dit à Terraform d'attendre que la BDD soit créée avant de lancer le serveur
  depends_on = [aws_db_instance.ma_bdd]

  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              # On installe PHP et les modules pour communiquer avec MySQL
              dnf install -y httpd php php-mysqli mariadb105
              systemctl start httpd
              systemctl enable httpd
              
              # On crée une vraie page PHP dynamique !
              cat << 'PHP' > /var/www/html/index.php
              <?php
              $conn = new mysqli("${aws_db_instance.ma_bdd.address}", "admin", "CesiPassword2026!", "forumdb");
              if ($conn->connect_error) {
                  echo "<h1 style='color:red;'>Serveur 1 : Erreur de connexion a la Base de donnees !</h1>";
              } else {
                  echo "<h1 style='color:green;'>Serveur 1 : Connecte avec succes a Amazon RDS (MySQL) !</h1>";
                  echo "<p>Pret pour installer Vichan ou Lainchan !</p>";
              }
              ?>
              PHP
              
              # On supprime la page html par defaut
              rm -f /var/www/html/index.html
              EOF

  tags = { Name = "Serveur-Johann-PHP-1" }
}

# --- SERVEUR 2 ---
resource "aws_instance" "serveur_2" {
  ami                         = data.aws_ami.amazon_linux_2023.id 
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.private_2.id
  vpc_security_group_ids      = [aws_security_group.sg_web.id]
  associate_public_ip_address = false 
  user_data_replace_on_change = true
  depends_on                  = [aws_db_instance.ma_bdd]

  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y httpd php php-mysqli mariadb105
              systemctl start httpd
              systemctl enable httpd
              
              cat << 'PHP' > /var/www/html/index.php
              <?php
              $conn = new mysqli("${aws_db_instance.ma_bdd.address}", "admin", "CesiPassword2026!", "forumdb");
              if ($conn->connect_error) {
                  echo "<h1 style='color:red;'>Serveur 2 : Erreur de connexion a la Base de donnees !</h1>";
              } else {
                  echo "<h1 style='color:green;'>Serveur 2 : Connecte avec succes a Amazon RDS (MySQL) !</h1>";
                  echo "<p>Pret pour installer Vichan ou Lainchan !</p>";
              }
              ?>
              PHP
              
              rm -f /var/www/html/index.html
              EOF

  tags = { Name = "Serveur-Johann-PHP-2" }
}

# ==========================================
# 5. LE LOAD BALANCER
# ==========================================
resource "aws_lb" "mon_alb" {
  name               = "johann-alb-tp"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.sg_alb.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

resource "aws_lb_target_group" "mon_tg" {
  name     = "johann-tg-tp"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.mon_vpc_tp.id

  health_check {
    path                = "/"
    port                = 80
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
  }
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.mon_alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mon_tg.arn
  }
}

resource "aws_lb_target_group_attachment" "att_1" {
  target_group_arn = aws_lb_target_group.mon_tg.arn
  target_id        = aws_instance.serveur_1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "att_2" {
  target_group_arn = aws_lb_target_group.mon_tg.arn
  target_id        = aws_instance.serveur_2.id
  port             = 80
}

# --- L'OUTPUT FINAL ---
output "adresse_du_site_web" {
  description = "Copie-colle ce lien DNS dans ton navigateur :"
  value       = aws_lb.mon_alb.dns_name
}