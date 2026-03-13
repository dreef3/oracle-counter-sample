package com.example.counter;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Emulates 10,000 accounts × 3 output channels × 2 formats × 7 days
 * = 420,000 distinct (account, channel, format, date) dimension combos.
 *
 * One call to get_next_report_number() is issued per combo.
 * Every call must return sequence number 1, proving that counters are
 * fully independent across all four dimensions.
 */
@SpringBootTest
class LargeScaleSequencingTest {

    // ── Dimensions ────────────────────────────────────────────────────────────
    private static final int      ACCOUNTS  = 10_000;
    private static final String[] CHANNELS  = {"EMAIL", "PRINT", "PORTAL"};
    private static final String[] FORMATS   = {"PDF", "CSV"};
    private static final int      DAYS      = 7;

    // Prefix lets @BeforeEach / @AfterEach wipe exactly these rows without
    // touching any other test data (e.g. the "PAR_TEST" rows from the other test).
    private static final String ACCOUNT_PREFIX = "LS_";

    private static final int THREADS     = 50;
    private static final int TOTAL_TASKS = ACCOUNTS * CHANNELS.length * FORMATS.length * DAYS;
    // 10 000 × 3 × 2 × 7 = 420 000

    @Autowired
    JdbcTemplate jdbcTemplate;

    @BeforeEach
    @AfterEach
    void cleanupLargeScaleRows() {
        jdbcTemplate.update(
            "DELETE FROM report_number_seq WHERE account_number LIKE ?",
            ACCOUNT_PREFIX + "%");
    }

    @Test
    void allDimensionCombosGetIndependentSequenceStartingAtOne() throws InterruptedException {

        ConcurrentLinkedQueue<String> dbErrors    = new ConcurrentLinkedQueue<>();
        AtomicInteger                 wrongSeqNum = new AtomicInteger();
        CountDownLatch                done        = new CountDownLatch(TOTAL_TASKS);
        ExecutorService               pool        = Executors.newFixedThreadPool(THREADS);

        for (int a = 1; a <= ACCOUNTS; a++) {
            String account = String.format("%s%05d", ACCOUNT_PREFIX, a);
            for (String channel : CHANNELS) {
                for (String format : FORMATS) {
                    for (int dayOffset = 0; dayOffset < DAYS; dayOffset++) {
                        final int d = dayOffset;
                        pool.submit(() -> {
                            try {
                                String num = jdbcTemplate.queryForObject(
                                    "SELECT get_next_report_number(?, ?, ?, TRUNC(SYSDATE) - ?) FROM DUAL",
                                    String.class,
                                    account, format, channel, d);
                                // Sequence must start at 1 for a brand-new key
                                // (number may be zero-padded, e.g. "0001")
                                if (Integer.parseInt(num) != 1) {
                                    wrongSeqNum.incrementAndGet();
                                }
                            } catch (Exception e) {
                                dbErrors.add(account + "/" + channel + "/" + format
                                    + "/day-" + d + ": " + e.getMessage());
                            } finally {
                                done.countDown();
                            }
                        });
                    }
                }
            }
        }

        boolean finished = done.await(15, TimeUnit.MINUTES);
        pool.shutdown();

        assertThat(dbErrors)
            .as("No DB errors across %,d dimension combos", TOTAL_TASKS)
            .isEmpty();

        assertThat(finished)
            .as("All %,d tasks must complete within 15 min", TOTAL_TASKS)
            .isTrue();

        assertThat(wrongSeqNum.get())
            .as("Every (account, channel, format, date) combo must return sequence 1 "
              + "on its first call – counters are independent")
            .isZero();
    }
}
