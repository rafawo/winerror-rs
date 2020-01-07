//! Rust abstractions of windows error code definitions for the Win32 API functions.
//!
//! Values are 32 bit values layed out as follows:
//! ```text
//!  3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1
//!  1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
//! +---+-+-+-----------------------+-------------------------------+
//! |Sev|C|R|     Facility          |               Code            |
//! +---+-+-+-----------------------+-------------------------------+
//!
//! where
//!
//!     Sev - is the severity code
//!
//!         00 - Success
//!         01 - Informational
//!         10 - Warning
//!         11 - Error
//!
//!     C - is the Customer code flag
//!
//!     R - is a reserved bit
//!
//!     Facility - is the facility code
//!
//!     Code - is the facility's status code
//! ```
//!
//! HRESULTs are 32 bit values layed out as follows:
//! ```text
//!  3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1
//!  1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
//! +-+-+-+-+-+---------------------+-------------------------------+
//! |S|R|C|N|r|    Facility         |               Code            |
//! +-+-+-+-+-+---------------------+-------------------------------+
//!
//! where
//!
//!     S - Severity - indicates success/fail
//!
//!         0 - Success
//!         1 - Fail (COERROR)
//!
//!     R - reserved portion of the facility code, corresponds to NT's
//!             second severity bit.
//!
//!     C - reserved portion of the facility code, corresponds to NT's
//!             C field.
//!
//!     N - reserved portion of the facility code. Used to indicate a
//!             mapped NT status value.
//!
//!     r - reserved portion of the facility code. Reserved for internal
//!             use. Used to indicate HRESULT values that are not status
//!             values, but are instead message ids for display strings.
//!
//!     Facility - is the facility code
//!
//!     Code - is the facility's status code
//! ```
//!

#![cfg_attr(not(feature = "std"), no_std)]
