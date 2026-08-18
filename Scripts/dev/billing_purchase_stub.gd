extends Node

## Smoke-only BillingClient stand-in. Records purchase(product_id, purchase_option_id).
## Never used in production. apply_smoke_billing_state refuses this outside isolation.

var last_product_id: String = ""
var last_purchase_option_id: String = ""
var last_offer_id: String = ""


func purchase(product_id: String, purchase_option_id: String = "", offer_id: String = "", is_offer_personalized: bool = false) -> Dictionary:
	last_product_id = product_id
	last_purchase_option_id = purchase_option_id
	last_offer_id = offer_id
	return {"response_code": 0, "debug_message": ""}
