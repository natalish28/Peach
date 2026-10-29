# Architecture

C4 level 2 (containers), updated for Lab 6: the agenda-parser function, Bedrock, and the two
new arrows, **parse** and **save**. Earlier labs' containers (reports pipeline, CloudFront)
are included for context.

```mermaid
flowchart LR
  user([User]) -->|HTTPS| web["Frontend<br/>Next.js static export<br/>S3 + CloudFront"]
  web -->|sign in| cognito["Amazon Cognito<br/>(Google / password)"]
  web -->|"save: POST /api/v1/agendas<br/>(Bearer ID token)"| api["API Lambda<br/>FastAPI, in VPC"]
  api -->|SQL| aurora[("Aurora Serverless v2<br/>PostgreSQL")]
  web -->|"parse: POST text, today, tz<br/>(Bearer ID token)"| parser["agenda-parser Lambda<br/>Python, outside the VPC"]
  parser -->|"verify token (JWKS)"| cognito
  parser -->|"Messages API<br/>bedrock-mantle:CreateInference"| bedrock["Amazon Bedrock<br/>Claude"]
  parser -.->|"one JSON log line per parse"| logs["CloudWatch Logs"]
  budget["AWS Budget $5/month"] -.->|email alarm| owner([Owner])
```

The parser never touches the database and never writes: it returns JSON to the browser. The
browser pre-fills the agenda form, and **save** goes through the normal API with its usual
validation, together with the model's suggestion (`agendas.ai_suggestion`). See
[ADR 0006](adr/0006-llm-agenda-parsing.md).
