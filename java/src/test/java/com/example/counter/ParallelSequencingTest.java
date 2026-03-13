package com.example.counter;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.Set;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Fires 12 concurrent threads, each calling get_next_report_number() 10 times
 * (120 total calls). Verifies that every returned value is unique and that
 * together they form an unbroken sequence 0001–0120.
 */
@SpringBootTest
class ParallelSequencingTest {

    private static final int THREADS          = 12;
    private static final int CALLS_PER_THREAD = 10;
    private static final int TOTAL_CALLS      = THREADS * CALLS_PER_THREAD;

    // Dedicated key that is only used by this test
    private static final String ACCOUNT  = "PAR_TEST";
    private static final String FORMAT   = "PDF";
    private static final String CHANNEL  = "CONCURRENT";

    @Autowired
    JdbcTemplate jdbcTemplate;

    @BeforeEach
    void cleanupTestKey() {
        jdbcTemplate.update(
            "DELETE FROM report_number_seq "
          + "WHERE account_number = ? AND format = ? AND output_channel = ?",
            ACCOUNT, FORMAT, CHANNEL);
    }

    @Test
    void twelveThreadsProduceUniqueSequentialNumbers() throws InterruptedException {
        ConcurrentLinkedQueue<String> results = new ConcurrentLinkedQueue<>();
        CountDownLatch ready  = new CountDownLatch(THREADS); // all threads start together
        CountDownLatch done   = new CountDownLatch(THREADS);
        ExecutorService pool  = Executors.newFixedThreadPool(THREADS);

        for (int t = 0; t < THREADS; t++) {
            pool.submit(() -> {
                ready.countDown();
                try {
                    ready.await(); // wait until all threads are ready, then burst together
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
                try {
                    for (int c = 0; c < CALLS_PER_THREAD; c++) {
                        String num = jdbcTemplate.queryForObject(
                            "SELECT get_next_report_number(?, ?, ?, TRUNC(SYSDATE)) FROM DUAL",
                            String.class,
                            ACCOUNT, FORMAT, CHANNEL);
                        results.add(num);
                    }
                } finally {
                    done.countDown();
                }
            });
        }

        boolean finished = done.await(60, TimeUnit.SECONDS);
        pool.shutdown();

        assertThat(finished)
            .as("All threads should complete within 60 s")
            .isTrue();

        assertThat(results)
            .as("Total number of results")
            .hasSize(TOTAL_CALLS);

        Set<String> unique = Set.copyOf(results);
        assertThat(unique)
            .as("Every result must be unique – no duplicate sequence numbers")
            .hasSize(TOTAL_CALLS);

        Set<Integer> expected = IntStream.rangeClosed(1, TOTAL_CALLS)
            .boxed()
            .collect(Collectors.toSet());
        Set<Integer> actual = results.stream()
            .map(Integer::parseInt)
            .collect(Collectors.toSet());

        assertThat(actual)
            .as("Results must form an unbroken sequence from 1 to " + TOTAL_CALLS)
            .isEqualTo(expected);
    }
}
