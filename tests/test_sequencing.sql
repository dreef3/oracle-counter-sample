-- =============================================================
-- tests/test_sequencing.sql
-- PL/SQL test suite for get_next_report_number.
--
-- Exit behaviour:
--   All assertions are collected; if any fail the block raises
--   ORA-20999 so SQLPlus exits with a non-zero status, which
--   GitHub Actions treats as a failed step.
-- =============================================================

WHENEVER SQLERROR EXIT FAILURE ROLLBACK;
SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
    -- ── helpers ──────────────────────────────────────────────
    v_result     VARCHAR2(10);
    v_failures   NUMBER       := 0;
    v_tests_run  NUMBER       := 0;

    PROCEDURE assert_eq(
        p_test_name  IN VARCHAR2,
        p_expected   IN VARCHAR2,
        p_actual     IN VARCHAR2
    ) IS
    BEGIN
        v_tests_run := v_tests_run + 1;
        IF p_actual = p_expected THEN
            DBMS_OUTPUT.PUT_LINE('  PASS  [' || p_test_name || '] got: ' || p_actual);
        ELSE
            v_failures := v_failures + 1;
            DBMS_OUTPUT.PUT_LINE('  FAIL  [' || p_test_name || '] '
                || 'expected=' || p_expected
                || '  actual=' || p_actual);
        END IF;
    END assert_eq;

BEGIN
    DBMS_OUTPUT.PUT_LINE('==============================================');
    DBMS_OUTPUT.PUT_LINE(' get_next_report_number – sequencing tests');
    DBMS_OUTPUT.PUT_LINE('==============================================');

    -- ──────────────────────────────────────────────────────────
    -- T1: Increment an existing counter (seeded at 5 → expect 6)
    -- ──────────────────────────────────────────────────────────
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '-- T1: Existing counter increments correctly');

    v_result := get_next_report_number('ACC001', 'PDF', 'EMAIL', SYSDATE);
    assert_eq('T1a: ACC001/PDF/EMAIL call 1', '0006', v_result);

    v_result := get_next_report_number('ACC001', 'PDF', 'EMAIL', SYSDATE);
    assert_eq('T1b: ACC001/PDF/EMAIL call 2', '0007', v_result);

    v_result := get_next_report_number('ACC001', 'PDF', 'EMAIL', SYSDATE);
    assert_eq('T1c: ACC001/PDF/EMAIL call 3', '0008', v_result);

    -- ──────────────────────────────────────────────────────────
    -- T2: Second account – seeded at 1 → expect 2 then 3
    -- ──────────────────────────────────────────────────────────
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '-- T2: Different account increments independently');

    v_result := get_next_report_number('ACC002', 'XLSX', 'PORTAL', SYSDATE);
    assert_eq('T2a: ACC002/XLSX/PORTAL call 1', '0002', v_result);

    v_result := get_next_report_number('ACC002', 'XLSX', 'PORTAL', SYSDATE);
    assert_eq('T2b: ACC002/XLSX/PORTAL call 2', '0003', v_result);

    -- ──────────────────────────────────────────────────────────
    -- T3: Brand-new key (no seed row) → starts at 1
    -- ──────────────────────────────────────────────────────────
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '-- T3: New key – INSERT path used, starts at 0001');

    v_result := get_next_report_number('ACC003', 'CSV', 'SFTP', SYSDATE);
    assert_eq('T3a: ACC003/CSV/SFTP call 1', '0001', v_result);

    v_result := get_next_report_number('ACC003', 'CSV', 'SFTP', SYSDATE);
    assert_eq('T3b: ACC003/CSV/SFTP call 2', '0002', v_result);

    -- ──────────────────────────────────────────────────────────
    -- T4: Same key but different date → independent sequence
    -- ──────────────────────────────────────────────────────────
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '-- T4: Date boundary – different date restarts at 0001');

    -- Tomorrow has no seed row
    v_result := get_next_report_number('ACC001', 'PDF', 'EMAIL', SYSDATE + 1);
    assert_eq('T4a: ACC001/PDF/EMAIL tomorrow call 1', '0001', v_result);

    v_result := get_next_report_number('ACC001', 'PDF', 'EMAIL', SYSDATE + 1);
    assert_eq('T4b: ACC001/PDF/EMAIL tomorrow call 2', '0002', v_result);

    -- Yesterday's row (seeded at 12) must not be affected
    v_result := get_next_report_number('ACC001', 'PDF', 'EMAIL', SYSDATE - 1);
    assert_eq('T4c: ACC001/PDF/EMAIL yesterday call 1', '0013', v_result);

    -- ──────────────────────────────────────────────────────────
    -- T5: Different output channel on same account/format/date
    -- ──────────────────────────────────────────────────────────
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '-- T5: Channel isolation');

    -- ACC001/PDF/PRINT today has no seed row (only yesterday's)
    v_result := get_next_report_number('ACC001', 'PDF', 'PRINT', SYSDATE);
    assert_eq('T5a: ACC001/PDF/PRINT today call 1', '0001', v_result);

    v_result := get_next_report_number('ACC001', 'PDF', 'PRINT', SYSDATE);
    assert_eq('T5b: ACC001/PDF/PRINT today call 2', '0002', v_result);

    -- ──────────────────────────────────────────────────────────
    -- T6: Zero-padding – counter reaching 10, 100, 1000
    -- ──────────────────────────────────────────────────────────
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '-- T6: Zero-padding at decade boundaries');

    -- Pre-position a key at 9 then call once more
    INSERT INTO report_number_seq
        (account_number, format, output_channel, report_date, last_number)
    VALUES ('PADTEST', 'PDF', 'EMAIL', TRUNC(SYSDATE), 9);
    COMMIT;

    v_result := get_next_report_number('PADTEST', 'PDF', 'EMAIL', SYSDATE);
    assert_eq('T6a: tenth call zero-padded', '0010', v_result);

    UPDATE report_number_seq
       SET last_number = 99
     WHERE account_number = 'PADTEST'
       AND format = 'PDF'
       AND output_channel = 'EMAIL'
       AND report_date = TRUNC(SYSDATE);
    COMMIT;

    v_result := get_next_report_number('PADTEST', 'PDF', 'EMAIL', SYSDATE);
    assert_eq('T6b: hundredth call zero-padded', '0100', v_result);

    UPDATE report_number_seq
       SET last_number = 999
     WHERE account_number = 'PADTEST'
       AND format = 'PDF'
       AND output_channel = 'EMAIL'
       AND report_date = TRUNC(SYSDATE);
    COMMIT;

    v_result := get_next_report_number('PADTEST', 'PDF', 'EMAIL', SYSDATE);
    assert_eq('T6c: thousandth call zero-padded', '1000', v_result);

    -- ──────────────────────────────────────────────────────────
    -- Summary
    -- ──────────────────────────────────────────────────────────
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '==============================================');
    DBMS_OUTPUT.PUT_LINE(' Results: '
        || (v_tests_run - v_failures) || ' passed, '
        || v_failures || ' failed'
        || ' (total: ' || v_tests_run || ')');
    DBMS_OUTPUT.PUT_LINE('==============================================');

    IF v_failures > 0 THEN
        RAISE_APPLICATION_ERROR(-20999,
            v_failures || ' test(s) FAILED – see output above.');
    END IF;
END;
/

EXIT SUCCESS;
