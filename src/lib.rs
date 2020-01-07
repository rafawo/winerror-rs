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

extern crate alloc;

use alloc::string::String;
use alloc::vec::Vec;

#[derive(Debug, Clone)]
pub struct Severity {
    name: String,
    value: i32,
}

impl Severity {
    pub fn new(name: &str, value: i32) -> Self {
        Severity {
            name: String::from(name),
            value,
        }
    }

    pub fn name(&self) -> &str {
        &self.name
    }

    pub fn value(&self) -> i32 {
        self.value
    }
}

#[derive(Debug, Clone)]
pub struct Facility {
    name: String,
    value: i32,
    symbolic_name: String,
}

impl Facility {
    pub fn new(name: &str, value: i32, symbolic_name: String) -> Self {
        Facility {
            name: String::from(name),
            value,
            symbolic_name: String::from(symbolic_name),
        }
    }

    pub fn name(&self) -> &str {
        &self.name
    }

    pub fn value(&self) -> i32 {
        self.value
    }

    pub fn symbolic_name(&self) -> &str {
        &self.symbolic_name
    }
}

pub enum ErrorCodeMemberError {
    WrongId(i32),
    WrongSeverity(i32),
    WrongFacility(i32),
}

#[derive(Debug, Clone)]
pub struct ErrorCode {
    id: i32,
    severity: i32,
    facility: i32,
    symbolic_name: String,
    message: Vec<String>,
}

impl ErrorCode {
    #[allow(overflowing_literals)]
    pub fn new(
        id: i32,
        severity: i32,
        facility: i32,
        symbolic_name: &str,
    ) -> Result<Self, ErrorCodeMemberError> {
        if id & 0xFFFF0000 > 0 {
            return Err(ErrorCodeMemberError::WrongId(id));
        }

        if severity & 0xFFFFFFFC > 0 {
            return Err(ErrorCodeMemberError::WrongSeverity(severity));
        }

        if facility & 0xFFFFF000 > 0 {
            return Err(ErrorCodeMemberError::WrongFacility(facility));
        }

        Ok(ErrorCode {
            id,
            severity,
            facility,
            symbolic_name: String::from(symbolic_name),
            message: Vec::new(),
        })
    }

    pub fn id(&self) -> i32 {
        self.id
    }

    pub fn severity(&self) -> i32 {
        self.severity
    }

    pub fn facility(&self) -> i32 {
        self.facility
    }

    pub fn symbolic_name(&self) -> &str {
        &self.symbolic_name
    }

    pub fn set_message(&mut self, message: &[String]) {
        for line in message {
            self.message.push(String::from(line));
        }
    }

    pub fn message(&self) -> &[String] {
        &self.message[0..self.message.len()]
    }

    pub fn value(&self) -> i32 {
        (self.severity << 30) | (self.facility << 16) | self.id
    }
}
