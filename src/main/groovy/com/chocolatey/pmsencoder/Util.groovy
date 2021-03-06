package com.chocolatey.pmsencoder

import net.pms.PMS

@groovy.transform.CompileStatic
class Util {
    public static List<String> toStringList(Object maybeList, boolean split = false) {
        if (maybeList == null) {
            // empty list
            return []
        } else {
            if (maybeList instanceof List) {
                // stringify each element
                return maybeList.collect { it.toString() }
            } else if (split) {
                // split along whitespace
                return maybeList.toString().tokenize()
            } else {
                // 1-element list
                return [ maybeList.toString() ]
            }
        }
    }

    public static <T> T guard(T defaultValue, Closure<T> closure) {
        T result
        try {
            result = closure()
        } catch (Exception e) {
            result = defaultValue
        }
        return result
    }

    public static String shellQuote(Object obj) {
        if (obj == null) {
            return null
        } else {
            String uri = obj.toString()
            // double quote a URI to make it safe for cmd.exe
            // XXX need to test this
            return PMS.get().isWindows() ? '"' + uri.replaceAll('"', '""') + '"' : uri
        }
    }
}
