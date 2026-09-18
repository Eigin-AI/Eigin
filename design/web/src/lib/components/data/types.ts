/** Any value a JSON document can hold. */
export type Json = string | number | boolean | null | Json[] | { [key: string]: Json };
