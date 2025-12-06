# Manual Dynatrace Alert Creation Instructions

Since the API approach is encountering issues, here are instructions for manually creating alerts in the Dynatrace UI:

1. Log in to the Dynatrace console: https://qpm46186.live.dynatrace.com
2. Navigate to Settings > Anomaly detection > Metric events
3. Click "Add metric event" button
4. For each service, create the following alerts:

## Response Time Alert
- Summary: Response Time Alert - [Service Name]
- Metric: builtin:service.response.time
- Entity selector: entityId("[SERVICE_ENTITY_ID]")
- Alert condition: above
- Threshold: 500
- Violating samples: 3
- Samples: 5
- Dealerting samples: 5
- Event title: Response Time Alert - [Service Name]
- Event description: The response time exceeded the threshold of 500ms

## Error Rate Alert
- Summary: Error Rate Alert - [Service Name]
- Metric: builtin:service.errors.server.rate
- Entity selector: entityId("[SERVICE_ENTITY_ID]")
- Alert condition: above
- Threshold: 5
- Violating samples: 3
- Samples: 5
- Dealerting samples: 5
- Event title: Error Rate Alert - [Service Name]
- Event description: The error rate exceeded the threshold of 5%

## Service Entity IDs
- otel-demo-frontendproxy: KUBERNETES_SERVICE-774BB29BB3826F36
- otel-demo-frontend: KUBERNETES_SERVICE-774BB29BB3826F36
- otel-demo-checkoutservice: KUBERNETES_SERVICE-5F8F9D77A406B58B
- otel-demo-paymentservice: KUBERNETES_SERVICE-212BAD4A02BC6E2A
- otel-demo-cartservice: KUBERNETES_SERVICE-2AB2261E67D9CEBE
