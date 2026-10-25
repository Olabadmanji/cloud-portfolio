resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "prod-db-subnet-group"
  subnet_ids = [aws_subnet.db_2a.id, aws_subnet.db_2b.id]
}

resource "aws_db_instance" "mysql" {
  identifier             = "prod-db-mysql"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = "webappdb"
  username               = "admin"
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  multi_az               = true
  publicly_accessible    = false
  skip_final_snapshot    = true
}