package nl.mennovanhout.nspanel_app

/** Pure input gate. Times use Android uptime, including MotionEvent.downTime. */
class WakeTouchGuard(private val now: () -> Long, initiallyInteractive: Boolean) {
    var interactive = initiallyInteractive
        private set
    var until = if (initiallyInteractive) now() + 500 else Long.MAX_VALUE
        private set
    private var gesture = false
    private var blocked = false
    private var forwarded = false

    /** Returns true exactly when Flutter must receive CANCEL for an old gesture. */
    fun screen(on: Boolean): Boolean {
        if (on == interactive) return false
        interactive = on
        until = if (on) now() + 500 else Long.MAX_VALUE
        val cancel = !on && forwarded
        if (!on) {
            blocked = true
            forwarded = false
        }
        return cancel
    }

    fun protect() { until = maxOf(until.takeUnless { it == Long.MAX_VALUE } ?: 0, now() + 500) }

    /** start = first DOWN, finish = final UP/CANCEL; all other fingers share the gate. */
    fun allow(start: Boolean, finish: Boolean, downTime: Long, saver: Boolean): Boolean {
        if (start) {
            gesture = true
            blocked = !interactive || saver || downTime < until || now() < until
            forwarded = !blocked
        }
        val allow = gesture && !blocked && interactive
        if (finish) { gesture = false; forwarded = false; blocked = false }
        return allow
    }

    fun cancel(): Boolean {
        val result = forwarded
        forwarded = false
        blocked = true
        gesture = false
        return result
    }
}
