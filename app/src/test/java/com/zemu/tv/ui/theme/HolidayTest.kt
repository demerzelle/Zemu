package com.zemu.tv.ui.theme

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate

class HolidayTest {
    private fun on(s: String) = Holiday.today(LocalDate.parse(s))

    @Test fun easterDates() {
        assertEquals(LocalDate.parse("2026-04-05"), Holiday.easter(2026))
        assertEquals(LocalDate.parse("2027-03-28"), Holiday.easter(2027))
    }

    @Test fun picksTheHolidayInItsWindow() {
        assertEquals(Holiday.HALLOWEEN, on("2026-10-14"))
        assertEquals(Holiday.CHRISTMAS, on("2026-12-20"))
        assertEquals(Holiday.HANUKKAH, on("2026-12-06"))
        assertEquals(Holiday.NEWYEAR, on("2027-01-02"))
        assertEquals(Holiday.VALENTINE, on("2026-02-12"))
        assertEquals(Holiday.THANKSGIVING, on("2026-11-20"))
        assertEquals(Holiday.DIWALI, on("2026-11-07"))
    }

    @Test fun betweenHolidaysTheNextOneComesUp() = assertEquals(Holiday.JULY4, on("2026-06-10"))
}
