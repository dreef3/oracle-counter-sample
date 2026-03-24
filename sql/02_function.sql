-- =============================================================
-- 02_function.sql
-- Atomic, autonomous-transaction report-number generator.
--
-- Returns a zero-padded 4-digit string (e.g. '0001') that is
-- unique per (account_number, format, output_channel, report_date).
-- =============================================================

WHENEVER SQLERROR EXIT FAILURE ROLLBACK;

CREATE OR REPLACE FUNCTION get_next_report_number(
    p_account_number  IN VARCHAR2,
    p_format          IN VARCHAR2,
    p_output_channel  IN VARCHAR2,
    p_date            IN DATE
) RETURN VARCHAR2
IS
    v_next_number  NUMBER;
    v_trunc_date   DATE := TRUNC(p_date);
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    -- Optimistic INSERT for the very first call on this key.
    -- A concurrent INSERT on the same PK blocks until the winner commits,
    -- so the loser reliably gets DUP_VAL_ON_INDEX rather than a gap.
    BEGIN
        INSERT INTO report_number_seq
            (account_number, format, output_channel, report_date, last_number)
        VALUES
            (p_account_number, p_format, p_output_channel, v_trunc_date, 1);
        v_next_number := 1;
    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            -- Row exists: atomically increment and capture the new value.
            UPDATE report_number_seq
               SET last_number = last_number + 1
             WHERE account_number = p_account_number
               AND format         = p_format
               AND output_channel = p_output_channel
               AND report_date    = v_trunc_date
            RETURNING last_number INTO v_next_number;
    END;

    COMMIT;
    RETURN TO_CHAR(v_next_number, 'FM0000');
END;
/

SHOW ERRORS FUNCTION get_next_report_number;

PROMPT Function compiled successfully.
