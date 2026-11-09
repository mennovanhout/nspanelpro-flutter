package nl.mennovanhout.nspanel_app

import org.junit.Assert.*
import org.junit.Test

class WakeTouchGuardTest {
    private var time = 0L
    private fun gate(on: Boolean = true) = WakeTouchGuard({ time }, on)

    @Test fun boundaryAndWholeGesture() {
        val g = gate()
        time = 499
        assertFalse(g.allow(true, false, time, false))
        time = 600
        assertFalse(g.allow(false, false, 499, false)) // MOVE / extra finger
        assertFalse(g.allow(false, true, 499, false))
        assertTrue(g.allow(true, false, time, false))
        assertTrue(g.allow(false, true, time, false))
    }
    @Test fun exactBoundaryAndDelayedDown() {
        val g = gate()
        time = 500
        assertTrue(g.allow(true, true, 500, false))
        time = 700
        assertFalse(g.allow(true, true, 499, false))
    }
    @Test fun coldDarkAndRepeatedEvents() {
        val g = gate(false)
        assertFalse(g.allow(true, true, time, false))
        time = 1000
        g.screen(true)
        time = 1400
        g.screen(true)
        time = 1500
        assertTrue(g.allow(true, true, time, false))
    }
    @Test fun sleepCancelsOnceAndNeverReplays() {
        val g = gate()
        time = 500
        assertTrue(g.allow(true, false, time, false))
        assertTrue(g.screen(false))
        assertFalse(g.screen(false))
        time = 1000
        g.screen(true)
        time = 2000
        assertFalse(g.allow(false, true, 500, false))
        assertTrue(g.allow(true, true, time, false))
    }
    @Test fun screensaverTouchAndResume() {
        val g = gate()
        time = 1000
        assertFalse(g.allow(true, false, time, true))
        g.protect()
        time = 2000
        assertFalse(g.allow(false, true, 1000, false))
        g.screen(true) // normal resume does not re-arm
        assertTrue(g.allow(true, false, time, false))
        assertTrue(g.cancel())
        assertFalse(g.allow(false, true, time, false))
    }
}
