-- =============================================================
-- 02_function.sql
-- Atomic, autonomous-transaction report-number generator.
--
-- Returns a zero-padded 4-digit string (e.g. '0001') that is
-- unique per (account_number, format, output_channel, report_date).
-- Uses SELECT … FOR UPDATE + INSERT with DUP_VAL_ON_INDEX fallback
-- so concurrent callers never generate the same number.
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
    BEGIN
        -- Happy path: row already exists – lock it and bump the counter
        SELECT last_number + 1
          INTO v_next_number
          FROM report_number_seq
         WHERE account_number = p_account_number
           AND format         = p_format
           AND output_channel = p_output_channel
           AND report_date    = v_trunc_date
           FOR UPDATE;

        UPDATE report_number_seq
           SET last_number = v_next_number
         WHERE account_number = p_account_number
           AND format         = p_format
           AND output_channel = p_output_channel
           AND report_date    = v_trunc_date;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- First call for this key – race-safe insert
            BEGIN
                INSERT INTO report_number_seq
                    (account_number, format, output_channel, report_date, last_number)
                VALUES
                    (p_account_number, p_format, p_output_channel, v_trunc_date, 1);
                v_next_number := 1;
            EXCEPTION
                WHEN DUP_VAL_ON_INDEX THEN
                    -- Another session won the race; fall back to the UPDATE path
                    SELECT last_number + 1
                      INTO v_next_number
                      FROM report_number_seq
                     WHERE account_number = p_account_number
                       AND format         = p_format
                       AND output_channel = p_output_channel
                       AND report_date    = v_trunc_date
                       FOR UPDATE;

                    UPDATE report_number_seq
                       SET last_number = v_next_number
                     WHERE account_number = p_account_number
                       AND format         = p_format
                       AND output_channel = p_output_channel
                       AND report_date    = v_trunc_date;
            END;
    END;

    COMMIT;
    RETURN TO_CHAR(v_next_number, 'FM0000');
END;
/

SHOW ERRORS FUNCTION get_next_report_number;

PROMPT Function compiled successfully.
