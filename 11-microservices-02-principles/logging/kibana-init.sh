#!/bin/sh
set -e

echo "Waiting for Kibana..."
until curl -sf http://kibana:5601/api/status >/dev/null; do
  sleep 3
done

echo "Creating index pattern api-logs*..."
curl -sf -X POST "http://kibana:5601/api/saved_objects/index-pattern/api-logs?overwrite=true" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d '{"attributes":{"title":"api-logs*","timeFieldName":"timestamp"}}' >/dev/null

curl -sf -X POST "http://kibana:5601/api/kibana/settings/defaultIndex" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d '{"value":"api-logs"}' >/dev/null || true

echo "Creating visualization..."
curl -sf -X POST "http://kibana:5601/api/saved_objects/visualization/logs-by-service?overwrite=true" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d '{
    "attributes": {
      "title": "Logs by service",
      "visState": "{\"title\":\"Logs by service\",\"type\":\"pie\",\"params\":{\"addTooltip\":true,\"addLegend\":true,\"legendPosition\":\"right\",\"isDonut\":false},\"aggs\":[{\"id\":\"1\",\"enabled\":true,\"type\":\"count\",\"schema\":\"metric\",\"params\":{}},{\"id\":\"2\",\"enabled\":true,\"type\":\"terms\",\"schema\":\"segment\",\"params\":{\"field\":\"service.keyword\",\"size\":10,\"order\":\"desc\",\"orderBy\":\"1\"}}]}",
      "uiStateJSON": "{}",
      "description": "",
      "version": 1,
      "kibanaSavedObjectMeta": {
        "searchSourceJSON": "{\"index\":\"api-logs\",\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filter\":[]}"
      }
    },
    "references": [
      {"name": "kibanaSavedObjectMeta.searchSourceJSON.index", "type": "index-pattern", "id": "api-logs"}
    ]
  }' >/dev/null

echo "Creating dashboard API Logs..."
curl -sf -X POST "http://kibana:5601/api/saved_objects/dashboard/api-logs-dashboard?overwrite=true" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d '{
    "attributes": {
      "title": "API Logs",
      "hits": 0,
      "description": "Логи микросервисов API Gateway",
      "panelsJSON": "[{\"version\":\"7.17.21\",\"type\":\"visualization\",\"gridData\":{\"x\":0,\"y\":0,\"w\":48,\"h\":18,\"i\":\"1\"},\"panelIndex\":\"1\",\"embeddableConfig\":{},\"panelRefName\":\"panel_1\"}]",
      "optionsJSON": "{\"useMargins\":true,\"hidePanelTitles\":false}",
      "version": 1,
      "timeRestore": false,
      "kibanaSavedObjectMeta": {
        "searchSourceJSON": "{\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filter\":[]}"
      }
    },
    "references": [
      {"name": "panel_1", "type": "visualization", "id": "logs-by-service"}
    ]
  }' >/dev/null

echo "Kibana objects ready."
