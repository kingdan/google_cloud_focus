# ---------------------------------------------------------------------------
# Refinement: repairs FOCUS 1.0 column drift and adds missing cost measures.
#
# The derived table in focus.view.lkml was upgraded to the FOCUS 1.0 spec,
# which renames vendor extensions to the `x_` prefix and renames UsageAmount
# to ConsumedQuantity. The dimensions built on it were never updated, leaving
# 3 of 4 measures throwing BigQuery "column not found" errors.
#
# Additive only - delete this file to revert every change below.
# ---------------------------------------------------------------------------

include: "/views/focus.view.lkml"

view: +focus {

  ##### Repair drifted column references #####

  # was ${TABLE}.gc_Credits - also unbreaks the gc_Credits UNNEST join
  dimension: gc_credits {
    sql: ${TABLE}.x_Credits ;;
  }

  # was ${TABLE}.gc_CostType
  dimension: gc_cost_type {
    sql: ${TABLE}.x_CostType ;;
  }

  # was ${TABLE}.UsageAmount, and typed as string despite being summed
  dimension: usage_amount {
    type: number
    sql: ${TABLE}.ConsumedQuantity ;;
  }

  # No gc_Cost column exists in the derived table under FOCUS 1.0, so this
  # measure cannot be repaired - hide it rather than leave a field that
  # errors whenever a user picks it. Use Total Billed Cost instead.
  measure: total_gc_cost {
    hidden: yes
  }

  ##### Add the cost measures a billing model needs #####

  measure: total_billed_cost {
    type: sum
    label: "Total Billed Cost"
    description: "Sum of Billed Cost - the basis for invoicing, inclusive of all reduced rates and discounts. This is what was actually charged."
    value_format_name: usd
    sql: ${billed_cost} ;;
  }

  measure: total_effective_cost {
    type: sum
    label: "Total Effective Cost"
    description: "Sum of Effective Cost - the amortized cost after applying all discounts and the applicable portion of prepaid commitments."
    value_format_name: usd
    sql: ${effective_cost} ;;
  }

  measure: total_contracted_cost {
    type: sum
    label: "Total Contracted Cost"
    description: "Sum of Contracted Cost - contracted unit price multiplied by pricing quantity, before commitment-based discounts."
    value_format_name: usd
    sql: ${contracted_cost} ;;
  }

  ##### Effective Savings Rate #####
  #
  # Tax and adjustment rows carry a Billed Cost but zero List Cost, which
  # drags any naive list-vs-effective ratio negative. Both sides of the
  # ratio are therefore restricted to ChargeCategory = "usage" so the
  # measure stays correct no matter how the user slices it.

  measure: list_cost_usage_only {
    type: sum
    hidden: yes
    sql: ${list_cost} ;;
    filters: [charge_category: "usage"]
  }

  measure: effective_cost_usage_only {
    type: sum
    hidden: yes
    sql: ${effective_cost} ;;
    filters: [charge_category: "usage"]
  }

  measure: effective_savings_rate {
    type: number
    label: "Effective Savings Rate"
    description: "Percentage saved against list price on usage charges: 1 - (Effective Cost / List Cost). Excludes tax and adjustments, which have no list price."
    value_format_name: percent_1
    sql: 1.0 - (${effective_cost_usage_only} / NULLIF(${list_cost_usage_only}, 0)) ;;
  }
}
