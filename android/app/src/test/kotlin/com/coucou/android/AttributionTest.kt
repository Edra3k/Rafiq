package com.coucou.android

import org.junit.Assert.assertEquals
import org.junit.Test

class AttributionTest {
    @Test fun nameAndRepoMatchPermission() {
        assertEquals("Rafiq for Android", Attribution.APP_NAME)
        assertEquals("https://github.com/Edra3k/Rafiq", Attribution.REPO_URL)
    }
}
