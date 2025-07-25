# ── Budget + alerts + monitoring ──────────────────────────

resource "oci_ons_notification_topic" "budget_alerts" {
  compartment_id = var.compartment_ocid
  name           = "homelab-budget-alerts"
}

resource "oci_ons_subscription" "budget_email" {
  compartment_id = var.compartment_ocid
  endpoint       = var.budget_alert_email
  protocol       = "EMAIL"
  topic_id       = oci_ons_notification_topic.budget_alerts.id
}

resource "oci_budget_budget" "budget" {
  compartment_id = var.tenancy_ocid
  target_type    = "COMPARTMENT"
  targets        = [var.tenancy_ocid]
  amount         = var.monthly_budget_usd
  reset_period   = "MONTHLY"
  display_name   = "homelab-budget"
}

resource "oci_budget_alert_rule" "any_spend" {
  budget_id      = oci_budget_budget.budget.id
  display_name   = "homelab-any-billable-spend"
  type           = "ACTUAL"
  threshold      = 1
  threshold_type = "PERCENTAGE"
  recipients     = var.budget_alert_email
  message        = "Billable spend detected - free tier exceeded"
}

resource "oci_monitoring_alarm" "node_cpu" {
  compartment_id        = var.compartment_ocid
  display_name          = "homelab-node-cpu-alarm"
  metric_compartment_id = var.compartment_ocid
  namespace             = "oci_computeagent"
  query                 = "CpuUtilization[5m].mean() > 80"
  severity              = "CRITICAL"
  body                  = "OKE node CPU utilization above 80% for 5 minutes"
  destinations          = [oci_ons_notification_topic.budget_alerts.id]
  is_enabled            = true
}
