@app.route("/donate")
def donate():
    donation_amount = expect_parameter("donation_amount")
    donation_donor = expect_parameter("donation_donor")
    fulfillment_url = flask.url_for("fulfillment", _external=True)
    order = dict(
        amount=donation_amount,
        extra=dict(donor=donation_donor, amount=donation_amount),
        fulfillment_url=fulfillment_url,
        summary="Donation to the GNU Taler project",
    )
    # ask backend to create new order
    order_resp = backend_post("order", dict(order=order))
    order_id = order_resp["order_id"]
    return flask.redirect(flask.url_for("fulfillment", order_id=order_id))


@app.route("/receipt")
def fulfillment():
    order_id = expect_parameter("order_id")
    pay_params = dict(order_id=order_id)

    # ask backend for status of payment
    pay_status = backend_get("check-payment", pay_params)

    if pay_status.get("payment_redirect_url"):
        return flask.redirect(pay_status["payment_redirect_url"])

    if pay_status.get("paid"):
        # The "extra" field in the contract terms can be used
        # by the merchant for free-form data, interpreted
        # by the merchant (avoids additional database access)
        extra = pay_status["contract_terms"]["extra"]
        return flask.render_template(
            "templates/fulfillment.html",
            donation_amount=extra["amount"],
            donation_donor=extra["donor"],
            order_id=order_id,
            currency=CURRENCY)

    # no pay_redirect but article not paid, this should never happen!
    err_abort(500, message="Internal error, invariant failed", json=pay_status)
