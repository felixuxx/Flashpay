/*
     This file is part of GNU Taler
     Copyright (C) 2023 Taler Systems SA

     GNU Taler is free software: you can redistribute it and/or modify it
     under the terms of the GNU Lesser General Public License as published
     by the Free Software Foundation, either version 3 of the License,
     or (at your option) any later version.

     GNU Taler is distributed in the hope that it will be useful, but
     WITHOUT ANY WARRANTY; without even the implied warranty of
     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
     Lesser General Public License for more details.

     You should have received a copy of the GNU Lesser General Public License
     along with this program.  If not, see <http://www.gnu.org/licenses/>.

     SPDX-License-Identifier: LGPL3.0-or-later

     Note: the LGPL does not apply to all components of GNU Taler,
     but it does apply to this file.
 */
/**
  * @file src/include/taler_attributes.h
  * @brief GNU Taler database event types, TO BE generated via https://gana.gnunet.org/
  */
#ifndef GNU_TALER_ATTRIBUTES_H
#define GNU_TALER_ATTRIBUTES_H

#ifdef __cplusplus
extern "C" {
#if 0 /* keep Emacsens' auto-indent happy */
}
#endif
#endif

/**
 * Legal name of the business/company.
 */
#define TALER_ATTRIBUTE_COMPANY_NAME "company_name"

/**
 * Legal country of registration of the business/company,
 * 2-letter country code using ISO 3166-2.
 */
#define TALER_ATTRIBUTE_REGISTRATION_COUNTRY "registration_country"

/**
 * Full name, when known/possible using "Lastname, Firstname(s)" format,
 * but "Firstname(s) Lastname" or "Firstname M. Lastname" should also be
 * tolerated (as is "Name", especially if the person only has one name).
 * If the person has no name, an empty string must be given.
 * NULL for not collected.
 */
#define TALER_ATTRIBUTE_FULL_NAME "full_name"

/**
 * True/false indicator if the individual is a politically
 * exposed person.
 */
#define TALER_ATTRIBUTE_PEP "pep"

/**
 * Street-level address. Usually includes the street and the house number. May
 * consist of multiple lines (separated by '\n'). Identifies a house in a city.  The city is not
 * part of the street.
 */
#define TALER_ATTRIBUTE_ADDRESS_STREET "street"

/**
 * City including postal code.  If available, a 2-letter country-code prefixes
 * the postal code, which is before the city (e.g. "DE-42289 Wuppertal").  If
 * the country code is unknown, the "CC-" prefix is missing.  If the ZIP code
 * is unknown, the hyphen is followed by a space ("DE- Wuppertal"). If only
 * the city name is known, it is prefixed by a space (" ").
 * If the city name is unknown, a space is at the end of the value.
 */
#define TALER_ATTRIBUTE_ADDRESS_CITY "city"

/**
 * Phone number (of business or individual).  Should come with the "+CC"
 * prefix including the country code.
 */
#define TALER_ATTRIBUTE_PHONE "phone"

/**
 * Email address (of business or individual).  Should be
 * in the format "user@hostname".
 */
#define TALER_ATTRIBUTE_EMAIL "email"

/**
 * Birthdate of the person, as far as known. YYYY-MM-DD, a value
 * of 0 (for DD, MM or even YYYY) is to be used for 'unknown'
 * according to official records.
 * Thus, 1950-00-00 stands for a birthdate in 1950 with unknown
 * day and month.  If official documents record January 1st or
 * some other date instead, that day may also be specified.
 * NULL for not collected.
 */
#define TALER_ATTRIBUTE_BIRTHDATE "birthdate"

/**
 * Citizenship(s) of the person using 2-letter country codes ("US", "DE",
 * "FR", "IT", etc.) separated by commas if multiple citizenships are
 * confirmed ("EN,US,DE"). Note that in the latter case it is not guaranteed
 * that all nationalities were necessarily recorded.  Empty string for
 * stateless persons.  NULL for not collected.
 */
#define TALER_ATTRIBUTE_NATIONALITIES "nationalities"

/**
 * Residence countries(s) of the person using 2-letter country codes ("US",
 * "DE", "FR", "IT", etc.) separated by commas if multiple residences are
 * confirmed ("EN,US,DE"). Note that in the latter case it is not guaranteed
 * that all residences were necessarily recorded.  Empty string for
 * international nomads.  NULL for not collected.
 */
#define TALER_ATTRIBUTE_RESIDENCES "residences"


#if 0 /* keep Emacsens' auto-indent happy */
{
#endif
#ifdef __cplusplus
}
#endif

#endif
