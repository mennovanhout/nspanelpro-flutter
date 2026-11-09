package nl.mennovanhout.nspanel_app

import org.junit.Assert.*
import org.junit.Test

class DisplayAwakeHoldTest {
    private val calls = mutableListOf<String>()
    private val hold = DisplayAwakeHold({ calls.add("acquire") }, { calls.add("release") })

    @Test fun darkStartDoesNotWakeAndEveryWakeReacquires() {
        hold.update(true, true, false)
        assertTrue(calls.isEmpty())
        repeat(2) {
            hold.update(true, true, true)
            // Resume, touch and duplicate SCREEN_ON must not add lock references.
            repeat(5) { hold.update(true, true, true) }
            hold.update(true, true, false)
            hold.update(true, true, false)
        }
        assertEquals(listOf("acquire", "release", "acquire", "release"), calls)
    }

    @Test fun backgroundWakeCannotHoldAnotherAppAwake() {
        hold.update(true, true, true)
        hold.update(true, false, true)
        hold.update(true, false, false)
        hold.update(true, false, true)
        assertEquals(listOf("acquire", "release"), calls)
        hold.update(true, true, true)
        assertEquals("acquire", calls.last())
    }

    @Test fun setupAndDestructionReleaseOwnership() {
        hold.update(true, true, true)
        hold.update(false, true, true)
        hold.update(false, true, false)
        hold.update(false, true, true)
        assertEquals(listOf("acquire", "release"), calls)
        hold.update(true, true, true)
        hold.update(false, false, false)
        assertEquals(listOf("acquire", "release", "acquire", "release"), calls)
    }
}
