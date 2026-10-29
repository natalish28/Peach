# Non-secret values only. Secrets (google_client_secret) and personal data (budget_email) are
# variables of the HCP Terraform workspace.

project_name = "peach"
region       = "us-east-1"

callback_urls = [
  "http://localhost:3000",
  "http://localhost:3000/auth/callback",
  "https://d1wt0wouypakka.cloudfront.net",
  "https://d1wt0wouypakka.cloudfront.net/auth/callback",
]
logout_urls = [
  "http://localhost:3000",
  "https://d1wt0wouypakka.cloudfront.net",
]

vpc_id          = "vpc-0b1ce9b8049973a6d"
route_table_ids = ["rtb-0346deaf72176a50f"]

reports_from_email = "shymanska.pn@ucu.edu.ua"
reports_to_email   = "shymanska.pn@ucu.edu.ua"

# The images the functions were created with. Later builds go through update-function-code.
report_builder_image_uri = "757159686525.dkr.ecr.us-east-1.amazonaws.com/peach-backend:99679ed60b30-reports-20261015085352"
agenda_parser_image_uri  = "757159686525.dkr.ecr.us-east-1.amazonaws.com/peach-backend:526ac5096733-ai-20261029105412"

parser_model = "us.amazon.nova-lite-v1:0"
