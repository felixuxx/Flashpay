SET search_path TO auditor;

CREATE TRIGGER auditor_notify_helper_deposits
    AFTER INSERT
    ON auditor.deposit_confirmations
EXECUTE PROCEDURE auditor_new_transactions_trigger();

CREATE OR REPLACE FUNCTION auditor_new_transactions_trigger()
    RETURNS trigger
    LANGUAGE plpgsql
AS $$
BEGIN
    -- TODO Add correct notify string
    PERFORM('NOTIFY XRE2709K6TYDBVARD9Y5SCZY7VHE4D5DKF0R8DHQ4X5T13E8X2X60');
    RETURN NEW;
END $$;
COMMENT ON FUNCTION auditor_new_transactions_trigger()
    IS 'Call auditor_call_db_notify on new entry';

