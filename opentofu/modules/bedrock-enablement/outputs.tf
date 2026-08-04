output "models_available_count" {
  description = "Number of Bedrock foundation models visible to this cell's credentials — a non-zero count is the practical proof Bedrock is reachable/enabled."
  value       = length(data.aws_bedrock_foundation_models.available.model_summaries)
}
