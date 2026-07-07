# Transcoding worker: consumes jobs from the SQS queue and writes the
# renditions to the encoded bucket. Stand-in for a managed transcoding
# service like AWS Elemental MediaConvert (see README).

data "archive_file" "transcoder" {
  type        = "zip"
  source_file = "${path.module}/lambda/transcoder.py"
  output_path = "${path.module}/build/transcoder.zip"
}

resource "aws_iam_role" "transcoder" {
  name = "${var.project}-transcoder"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "transcoder" {
  name = "transcoder-permissions"
  role = aws_iam_role.transcoder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ConsumeQueue"
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = aws_sqs_queue.this.arn
      },
      {
        Sid      = "ReadMasters"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.raw.arn}/*"
      },
      {
        Sid      = "WriteRenditions"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.encoded.arn}/*"
      },
      {
        Sid      = "UpdateMetadata"
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.this.arn
      },
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_lambda_function" "transcoder" {
  function_name    = "${var.project}-transcoder"
  role             = aws_iam_role.transcoder.arn
  runtime          = "python3.13"
  handler          = "transcoder.handler"
  filename         = data.archive_file.transcoder.output_path
  source_code_hash = data.archive_file.transcoder.output_base64sha256
  timeout          = 120
  memory_size      = 512

  environment {
    variables = {
      TABLE_NAME     = aws_dynamodb_table.videos.name
      ENCODED_BUCKET = aws_s3_bucket.encoded.id
      RENDITIONS     = join(",", var.renditions)
    }
  }
}

resource "aws_lambda_event_source_mapping" "transcoding_queue" {
  event_source_arn = aws_sqs_queue.transcoding.arn
  function_name    = aws_lambda_function.transcoder.arn
  batch_size       = 1
}
