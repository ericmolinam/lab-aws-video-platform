# Metadata DB: one item per video (title, status, storage keys, renditions).
resource "aws_dynamodb_table" "this" {
  name         = "${var.project}-database"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "video_id"

  attribute {
    name = "video_id"
    type = "S"
  }

  tags = {
    Name = "metadata-db"
  }
}
