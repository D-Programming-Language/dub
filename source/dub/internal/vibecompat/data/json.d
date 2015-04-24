module dub.internal.vibecompat.data.json;

version (Have_vibe_d) public import vibe.data.json;
else:

import dub.internal.vibecompat.data.utils;

import std.array;
import std.conv;
import std.datetime;
import std.exception;
import std.format;
import std.string;
import std.range;
import std.traits;

version = JsonLineNumbers;


/******************************************************************************/
/* public types                                                               */
/******************************************************************************/

/**
	Represents a single JSON value.

	Json values can have one of the types defined in the Json.Type enum. They
	behave mostly like values in ECMA script in the way that you can
	transparently perform operations on them. However, strict typechecking is
	done, so that operations between differently typed JSON values will throw
	an exception. Additionally, an explicit cast or using get!() or to!() is
	required to convert a JSON value to the corresponding static D type.
*/
struct Json {
	private {
		union {
			bool m_bool;
			long m_int;
			double m_float;
			string m_string;
			Json[] m_array;
			Json[string] m_object;
		};
		Type m_type = Type.undefined;
		uint m_magic = 0x1337f00d; // workaround for Appender bug
		string m_name;
	}

	/** Represents the run time type of a JSON value.
	*/
	enum Type {
		/// A non-existent value in a JSON object
		undefined,
		/// Null value
		null_,
		/// Boolean value
		bool_,
		/// 64-bit integer value
		int_,
		/// 64-bit floating point value
		float_,
		/// UTF-8 string
		string,
		/// Array of JSON values
		array,
		/// JSON object aka. dictionary from string to Json
		object
	}

	/// New JSON value of Type.undefined
	static @property Json undefined() { return Json(); }

	/// New JSON value of Type.object
	static @property Json emptyObject() { return Json(cast(Json[string])null); }

	/// New JSON value of Type.array
	static @property Json emptyArray() { return Json(cast(Json[])null); }

	version(JsonLineNumbers) int line;

	/**
		Constructor for a JSON object.
	*/
	this(typeof(null)) { m_type = Type.null_; }
	/// ditto
	this(bool v) { m_type = Type.bool_; m_bool = v; }
	/// ditto
	this(int v) { m_type = Type.int_; m_int = v; }
	/// ditto
	this(long v) { m_type = Type.int_; m_int = v; }
	/// ditto
	this(double v) { m_type = Type.float_; m_float = v; }
	/// ditto
	this(string v) { m_type = Type.string; m_string = v; }
	/// ditto
	this(Json[] v) { m_type = Type.array; m_array = v; }
	/// ditto
	this(Json[string] v) { m_type = Type.object; m_object = v; }

	/**
		Allows assignment of D values to a JSON value.
	*/
	ref Json opAssign(Json v){
		m_type = v.m_type;
		final switch(m_type){
			case Type.undefined: m_string = null; break;
			case Type.null_: m_string = null; break;
			case Type.bool_: m_bool = v.m_bool; break;
			case Type.int_: m_int = v.m_int; break;
			case Type.float_: m_float = v.m_float; break;
			case Type.string: m_string = v.m_string; break;
			case Type.array:
				m_array = v.m_array;
				if (m_magic == 0x1337f00d) { foreach (ref av; m_array) av.m_name = m_name; } else m_name = null;
				break;
			case Type.object:
				m_object = v.m_object;
				if (m_magic == 0x1337f00d) { foreach (k, ref av; m_object) av.m_name = m_name ~ "." ~ k; } else m_name = null;
				break;
		}
		return this;
	}
	/// ditto
	void opAssign(typeof(null)) { m_type = Type.null_; m_string = null; }
	/// ditto
	bool opAssign(bool v) { m_type = Type.bool_; m_bool = v; return v; }
	/// ditto
	int opAssign(int v) { m_type = Type.int_; m_int = v; return v; }
	/// ditto
	long opAssign(long v) { m_type = Type.int_; m_int = v; return v; }
	/// ditto
	double opAssign(double v) { m_type = Type.float_; m_float = v; return v; }
	/// ditto
	string opAssign(string v) { m_type = Type.string; m_string = v; return v; }
	/// ditto
	Json[] opAssign(Json[] v)
	{
		m_type = Type.array;
		m_array = v;
		if (m_magic == 0x1337f00d) foreach (ref av; m_array) av.m_name = m_name;
		return v;
	}
	/// ditto
	Json[string] opAssign(Json[string] v)
	{
		m_type = Type.object;
		m_object = v;
		if (m_magic == 0x1337f00d) foreach (k, ref av; m_object) av.m_name = m_name ~ "." ~ k;
		return v;
	}

	/**
		The current type id of this JSON object.
	*/
	@property Type type() const { return m_type; }

	/**
		Allows direct indexing of array typed JSON values.
	*/
	ref inout(Json) opIndex(size_t idx) inout { checkType!(Json[])(); return m_array[idx]; }

	/**
		Allows direct indexing of object typed JSON values using a string as
		the key.
	*/
	const(Json) opIndex(string key) const {
		checkType!(Json[string])();
		if( auto pv = key in m_object ) return *pv;
		Json ret = Json.undefined;
		ret.m_string = key;
		return ret;
	}
	/// ditto
	ref Json opIndex(string key){
		checkType!(Json[string])();
		if( auto pv = key in m_object )
			return *pv;
		m_object[key] = Json();
		m_object[key].m_type = Type.undefined; // DMDBUG: AAs are teh $H1T!!!11
		assert(m_object[key].type == Type.undefined);
		m_object[key].m_name = m_name ~ "." ~ key;
		m_object[key].m_string = key;
		return m_object[key];
	}

	/**
		Returns a slice of a JSON array.
	*/
	inout(Json[]) opSlice() inout { checkType!(Json[])(); return m_array; }
	///
	inout(Json[]) opSlice(size_t from, size_t to) inout { checkType!(Json[])(); return m_array[from .. to]; }

	/**
		Removes an entry from an object.
	*/
	void remove(string item) { checkType!(Json[string])(); m_object.remove(item); }

	/**
		Returns the number of entries of string, array or object typed JSON values.
	*/
	@property size_t length()
	const {
		checkType!(string, Json[], Json[string]);
		switch(m_type){
			case Type.string: return m_string.length;
			case Type.array: return m_array.length;
			case Type.object: return m_object.length;
			default: assert(false);
		}
	}

	/**
		Allows foreach iterating over JSON objects and arrays.
	*/
	int opApply(int delegate(ref Json obj) del)
	{
		checkType!(Json[], Json[string]);
		if( m_type == Type.array ){
			foreach( ref v; m_array )
				if( auto ret = del(v) )
					return ret;
			return 0;
		} else {
			foreach( ref v; m_object )
				if( v.type != Type.undefined )
					if( auto ret = del(v) )
						return ret;
			return 0;
		}
	}
	/// ditto
	int opApply(int delegate(ref const Json obj) del)
	const {
		checkType!(Json[], Json[string]);
		if( m_type == Type.array ){
			foreach( ref v; m_array )
				if( auto ret = del(v) )
					return ret;
			return 0;
		} else {
			foreach( ref v; m_object )
				if( v.type != Type.undefined )
					if( auto ret = del(v) )
						return ret;
			return 0;
		}
	}
	/// ditto
	int opApply(int delegate(ref size_t idx, ref Json obj) del)
	{
		checkType!(Json[]);
		foreach( idx, ref v; m_array )
			if( auto ret = del(idx, v) )
				return ret;
		return 0;
	}
	/// ditto
	int opApply(int delegate(ref size_t idx, ref const Json obj) del)
	const {
		checkType!(Json[]);
		foreach( idx, ref v; m_array )
			if( auto ret = del(idx, v) )
				return ret;
		return 0;
	}
	/// ditto
	int opApply(int delegate(ref string idx, ref Json obj) del)
	{
		checkType!(Json[string]);
		foreach( idx, ref v; m_object )
			if( v.type != Type.undefined )
				if( auto ret = del(idx, v) )
					return ret;
		return 0;
	}
	/// ditto
	int opApply(int delegate(ref string idx, ref const Json obj) del)
	const {
		checkType!(Json[string]);
		foreach( idx, ref v; m_object )
			if( v.type != Type.undefined )
				if( auto ret = del(idx, v) )
					return ret;
		return 0;
	}

	/**
		Converts the JSON value to the corresponding D type - types must match exactly.
	*/
	inout(T) opCast(T)() inout { return get!T; }
	/// ditto
	@property inout(T) get(T)()
	inout {
		checkType!T();
		static if( is(T == bool) ) return m_bool;
		else static if( is(T == double) ) return m_float;
		else static if( is(T == float) ) return cast(T)m_float;
		else static if( is(T == long) ) return m_int;
		else static if( is(T : long) ){ enforce(m_int <= T.max && m_int >= T.min); return cast(T)m_int; }
		else static if( is(T == string) ) return m_string;
		else static if( is(T == Json[]) ) return m_array;
		else static if( is(T == Json[string]) ) return m_object;
		else static assert("JSON can only be casted to (bool, long, double, string, Json[] or Json[string]. Not "~T.stringof~".");
	}
	/// ditto
	@property const(T) opt(T)(const(T) def = T.init)
	const {
		if( typeId!T != m_type ) return def;
		return get!T;
	}
	/// ditto
	@property T opt(T)(T def = T.init)
	{
		if( typeId!T != m_type ) return def;
		return get!T;
	}

	/**
		Converts the JSON value to the corresponding D type - types are converted as neccessary.
	*/
	@property inout(T) to(T)()
	inout {
		static if( is(T == bool) ){
			final switch( m_type ){
				case Type.undefined: return false;
				case Type.null_: return false;
				case Type.bool_: return m_bool;
				case Type.int_: return m_int != 0;
				case Type.float_: return m_float != 0;
				case Type.string: return m_string.length > 0;
				case Type.array: return m_array.length > 0;
				case Type.object: return m_object.length > 0;
			}
		} else static if( is(T == double) ){
			final switch( m_type ){
				case Type.undefined: return T.init;
				case Type.null_: return 0;
				case Type.bool_: return m_bool ? 1 : 0;
				case Type.int_: return m_int;
				case Type.float_: return m_float;
				case Type.string: return .to!double(cast(string)m_string);
				case Type.array: return double.init;
				case Type.object: return double.init;
			}
		} else static if( is(T == float) ){
			final switch( m_type ){
				case Type.undefined: return T.init;
				case Type.null_: return 0;
				case Type.bool_: return m_bool ? 1 : 0;
				case Type.int_: return m_int;
				case Type.float_: return m_float;
				case Type.string: return .to!float(cast(string)m_string);
				case Type.array: return float.init;
				case Type.object: return float.init;
			}
		}
		else static if( is(T == long) ){
			final switch( m_type ){
				case Type.undefined: return 0;
				case Type.null_: return 0;
				case Type.bool_: return m_bool ? 1 : 0;
				case Type.int_: return m_int;
				case Type.float_: return cast(long)m_float;
				case Type.string: return .to!long(m_string);
				case Type.array: return 0;
				case Type.object: return 0;
			}
		} else static if( is(T : long) ){
			final switch( m_type ){
				case Type.undefined: return 0;
				case Type.null_: return 0;
				case Type.bool_: return m_bool ? 1 : 0;
				case Type.int_: return cast(T)m_int;
				case Type.float_: return cast(T)m_float;
				case Type.string: return cast(T).to!long(cast(string)m_string);
				case Type.array: return 0;
				case Type.object: return 0;
			}
		} else static if( is(T == string) ){
			switch( m_type ){
				default: return toString();
				case Type.string: return m_string;
			}
		} else static if( is(T == Json[]) ){
			switch( m_type ){
				default: return Json([this]);
				case Type.array: return m_array;
			}
		} else static if( is(T == Json[string]) ){
			switch( m_type ){
				default: return Json(["value": this]);
				case Type.object: return m_object;
			}
		} else static assert("JSON can only be casted to (bool, long, double, string, Json[] or Json[string]. Not "~T.stringof~".");
	}

	/**
		Performs unary operations on the JSON value.

		The following operations are supported for each type:

		$(DL
			$(DT Null)   $(DD none)
			$(DT Bool)   $(DD ~)
			$(DT Int)    $(DD +, -, ++, --)
			$(DT Float)  $(DD +, -, ++, --)
			$(DT String) $(DD none)
			$(DT Array)  $(DD none)
			$(DT Object) $(DD none)
		)
	*/
	Json opUnary(string op)()
	const {
		static if( op == "~" ){
			checkType!bool();
			return Json(~m_bool);
		} else static if( op == "+" || op == "-" || op == "++" || op == "--" ){
			checkType!(long, double);
			if( m_type == Type.int_ ) mixin("return Json("~op~"m_int);");
			else if( m_type == Type.float_ ) mixin("return Json("~op~"m_float);");
			else assert(false);
		} else static assert("Unsupported operator '"~op~"' for type JSON.");
	}

	/**
		Performs binary operations between JSON values.

		The two JSON values must be of the same run time type or an exception
		will be thrown. Only the operations listed are allowed for each of the
		types.

		$(DL
			$(DT Null)   $(DD none)
			$(DT Bool)   $(DD &&, ||)
			$(DT Int)    $(DD +, -, *, /, %)
			$(DT Float)  $(DD +, -, *, /, %)
			$(DT String) $(DD ~)
			$(DT Array)  $(DD ~)
			$(DT Object) $(DD none)
		)
	*/
	Json opBinary(string op)(ref const(Json) other)
	const {
		enforce(m_type == other.m_type, "Binary operation '"~op~"' between "~.to!string(m_type)~" and "~.to!string(other.m_type)~" JSON objects.");
		static if( op == "&&" ){
			checkType!(bool)("'&&'"); other.checkType!(bool)("'&&'");
			return Json(m_bool && other.m_bool);
		} else static if( op == "||" ){
			checkType!(bool)("'||'"); other.checkType!(bool)("'||'");
			return Json(m_bool || other.m_bool);
		} else static if( op == "+" ){
			checkType!(double, long)("'+'"); other.checkType!(double, long)("'+'");
			if( m_type == Type.int_ ) return Json(m_int + other.m_int);
			else if( m_type == Type.float_ ) return Json(m_float + other.m_float);
			else assert(false);
		} else static if( op == "-" ){
			checkType!(double, long)("'-'"); other.checkType!(double, long)("'-'");
			if( m_type == Type.int_ ) return Json(m_int - other.m_int);
			else if( m_type == Type.float_ ) return Json(m_float - other.m_float);
			else assert(false);
		} else static if( op == "*" ){
			checkType!(double, long)("'*'"); other.checkType!(double, long)("'*'");
			if( m_type == Type.int_ ) return Json(m_int * other.m_int);
			else if( m_type == Type.float_ ) return Json(m_float * other.m_float);
			else assert(false);
		} else static if( op == "/" ){
			checkType!(double, long)("'/'"); other.checkType!(double, long)("'/'");
			if( m_type == Type.int_ ) return Json(m_int / other.m_int);
			else if( m_type == Type.float_ ) return Json(m_float / other.m_float);
			else assert(false);
		} else static if( op == "%" ){
			checkType!(double, long)("'%'"); other.checkType!(double, long)("'%'");
			if( m_type == Type.int_ ) return Json(m_int % other.m_int);
			else if( m_type == Type.float_ ) return Json(m_float % other.m_float);
			else assert(false);
		} else static if( op == "~" ){
			checkType!(string)("'~'"); other.checkType!(string)("'~'");
			if( m_type == Type.string ) return Json(m_string ~ other.m_string);
			else assert(false);
		} else static assert("Unsupported operator '"~op~"' for type JSON.");
	}
	/// ditto
	Json opBinary(string op)(Json other)
		if( op == "~" )
	{
		static if( op == "~" ){
			checkType!(string, Json[])("'~'"); other.checkType!(string, Json[])("'~'");
			if( m_type == Type.string ) return Json(m_string ~ other.m_string);
			else if( m_type == Type.array ) return Json(m_array ~ other.m_array);
			else assert(false);
		} else static assert("Unsupported operator '"~op~"' for type JSON.");
	}
	/// ditto
	void opOpAssign(string op)(Json other)
		if( op == "+" || op == "-" || op == "*" ||op == "/" || op == "%" )
	{
		enforce(m_type == other.m_type, "Binary operation '"~op~"' between "~.to!string(m_type)~" and "~.to!string(other.m_type)~" JSON objects.");
		static if( op == "+" ){
			if( m_type == Type.int_ ) m_int += other.m_int;
			else if( m_type == Type.float_ ) m_float += other.m_float;
			else enforce(false, "'+' only allowed for scalar types, not "~.to!string(m_type)~".");
		} else static if( op == "-" ){
			if( m_type == Type.int_ ) m_int -= other.m_int;
			else if( m_type == Type.float_ ) m_float -= other.m_float;
			else enforce(false, "'-' only allowed for scalar types, not "~.to!string(m_type)~".");
		} else static if( op == "*" ){
			if( m_type == Type.int_ ) m_int *= other.m_int;
			else if( m_type == Type.float_ ) m_float *= other.m_float;
			else enforce(false, "'*' only allowed for scalar types, not "~.to!string(m_type)~".");
		} else static if( op == "/" ){
			if( m_type == Type.int_ ) m_int /= other.m_int;
			else if( m_type == Type.float_ ) m_float /= other.m_float;
			else enforce(false, "'/' only allowed for scalar types, not "~.to!string(m_type)~".");
		} else static if( op == "%" ){
			if( m_type == Type.int_ ) m_int %= other.m_int;
			else if( m_type == Type.float_ ) m_float %= other.m_float;
			else enforce(false, "'%' only allowed for scalar types, not "~.to!string(m_type)~".");
		} /*else static if( op == "~" ){
			if( m_type == Type.string ) m_string ~= other.m_string;
			else if( m_type == Type.array ) m_array ~= other.m_array;
			else enforce(false, "'%' only allowed for scalar types, not "~.to!string(m_type)~".");
		}*/ else static assert("Unsupported operator '"~op~"' for type JSON.");
		assert(false);
	}
	/// ditto
	Json opBinary(string op)(bool other) const { checkType!bool(); mixin("return Json(m_bool "~op~" other);"); }
	/// ditto
	Json opBinary(string op)(long other) const { checkType!long(); mixin("return Json(m_int "~op~" other);"); }
	/// ditto
	Json opBinary(string op)(double other) const { checkType!double(); mixin("return Json(m_float "~op~" other);"); }
	/// ditto
	Json opBinary(string op)(string other) const { checkType!string(); mixin("return Json(m_string "~op~" other);"); }
	/// ditto
	Json opBinary(string op)(Json other)
	if (op == "~") {
		if (m_type == Type.array) return Json(m_array ~ other);
		else return Json(this ~ other);
	}
	/// ditto
	Json opBinaryRight(string op)(bool other) const { checkType!bool(); mixin("return Json(other "~op~" m_bool);"); }
	/// ditto
	Json opBinaryRight(string op)(long other) const { checkType!long(); mixin("return Json(other "~op~" m_int);"); }
	/// ditto
	Json opBinaryRight(string op)(double other) const { checkType!double(); mixin("return Json(other "~op~" m_float);"); }
	/// ditto
	Json opBinaryRight(string op)(string other) const if(op == "~") { checkType!string(); return Json(other ~ m_string); }
	/// ditto
	inout(Json)* opBinaryRight(string op)(string other) inout if(op == "in") {
		checkType!(Json[string])();
		auto pv = other in m_object;
		if( !pv ) return null;
		if( pv.type == Type.undefined ) return null;
		return pv;
	}

	/**
		Allows to access existing fields of a JSON object using dot syntax.
	*/
	@property const(Json) opDispatch(string prop)() const { return opIndex(prop); }
	/// ditto
	@property ref Json opDispatch(string prop)() { return opIndex(prop); }

	/**
		Compares two JSON values for equality.

		If the two values have different types, they are considered unequal.
		This differs with ECMA script, which performs a type conversion before
		comparing the values.
	*/
	bool opEquals(ref const Json other)
	const {
		if( m_type != other.m_type ) return false;
		final switch(m_type){
			case Type.undefined: return false;
			case Type.null_: return true;
			case Type.bool_: return m_bool == other.m_bool;
			case Type.int_: return m_int == other.m_int;
			case Type.float_: return m_float == other.m_float;
			case Type.string: return m_string == other.m_string;
			case Type.array: return m_array == other.m_array;
			case Type.object: return m_object == other.m_object;
		}
	}
	/// ditto
	bool opEquals(const Json other) const { return opEquals(other); }
	/// ditto
	bool opEquals(typeof(null)) const { return m_type == Type.null_; }
	/// ditto
	bool opEquals(bool v) const { return m_type == Type.bool_ && m_bool == v; }
	/// ditto
	bool opEquals(long v) const { return m_type == Type.int_ && m_int == v; }
	/// ditto
	bool opEquals(double v) const { return m_type == Type.float_ && m_float == v; }
	/// ditto
	bool opEquals(string v) const { return m_type == Type.string && m_string == v; }

	/**
		Compares two JSON values.

		If the types of the two values differ, the value with the smaller type
		id is considered the smaller value. This differs from ECMA script, which
		performs a type conversion before comparing the values.

		JSON values of type Object cannot be compared and will throw an
		exception.
	*/
	int opCmp(ref const Json other)
	const {
		if( m_type != other.m_type ) return m_type < other.m_type ? -1 : 1;
		final switch(m_type){
			case Type.undefined: return 0;
			case Type.null_: return 0;
			case Type.bool_: return m_bool < other.m_bool ? -1 : m_bool == other.m_bool ? 0 : 1;
			case Type.int_: return m_int < other.m_int ? -1 : m_int == other.m_int ? 0 : 1;
			case Type.float_: return m_float < other.m_float ? -1 : m_float == other.m_float ? 0 : 1;
			case Type.string: return m_string < other.m_string ? -1 : m_string == other.m_string ? 0 : 1;
			case Type.array: return m_array < other.m_array ? -1 : m_array == other.m_array ? 0 : 1;
			case Type.object:
				enforce(false, "JSON objects cannot be compared.");
				assert(false);
		}
	}



	/**
		Returns the type id corresponding to the given D type.
	*/
	static @property Type typeId(T)() {
		static if( is(T == typeof(null)) ) return Type.null_;
		else static if( is(T == bool) ) return Type.bool_;
		else static if( is(T == double) ) return Type.float_;
		else static if( is(T == float) ) return Type.float_;
		else static if( is(T : long) ) return Type.int_;
		else static if( is(T == string) ) return Type.string;
		else static if( is(T == Json[]) ) return Type.array;
		else static if( is(T == Json[string]) ) return Type.object;
		else static assert(false, "Unsupported JSON type '"~T.stringof~"'. Only bool, long, double, string, Json[] and Json[string] are allowed.");
	}

	/**
		Returns the JSON object as a string.

		For large JSON values use writeJsonString instead as this function will store the whole string
		in memory, whereas writeJsonString writes it out bit for bit.

		See_Also: writeJsonString, toPrettyString
	*/
	string toString()
	const {
		auto ret = appender!string();
		writeJsonString(ret, this);
		return ret.data;
	}

	/**
		Returns the JSON object as a "pretty" string.

		---
		auto json = Json(["foo": Json("bar")]);
		writeln(json.toPrettyString());

		// output:
		// {
		//     "foo": "bar"
		// }
		---

		Params:
			level = Specifies the base amount of indentation for the output. Indentation is always
				done using tab characters.

		See_Also: writePrettyJsonString, toString
	*/
	string toPrettyString(int level = 0)
	const {
		auto ret = appender!string();
		writePrettyJsonString(ret, this, level);
		return ret.data;
	}

	private void checkType(T...)(string op = null)
	const {
		bool found = false;
		foreach (t; T) if (m_type == typeId!t) found = true;
		if (found) return;
		if (T.length == 1) {
			throw new Exception(format("Got %s - expected %s.", this.displayName, typeId!(T[0]).to!string));
		} else {
			string types;
			foreach (t; T) {
				if (types.length) types ~= ", ";
				types ~= typeId!t.to!string;
			}
			throw new Exception(format("Got %s - expected one of %s.", this.displayName, types));
		}
	}

	private @property string displayName()
	const {
		if (m_name.length) return m_name ~ " of type " ~ m_type.to!string();
		else return "JSON of type " ~ m_type.to!string();
	}

	/*invariant()
	{
		assert(m_type >= Type.undefined && m_type <= Type.object);
	}*/
}


/******************************************************************************/
/* public functions                                                           */
/******************************************************************************/

/**
	Parses the given range as a JSON string and returns the corresponding Json object.

	The range is shrunk during parsing, leaving any remaining text that is not part of
	the JSON contents.

	Throws an Exception if any parsing error occured.
*/
Json parseJson(R)(ref R range, string filename, int* line)
	if( is(R == string) )
{
	import std.algorithm : min;

	assert(line !is null);
	Json ret;
	enforceJson(!range.empty, "JSON string is empty.", filename, 0);

	skipWhitespace(range, line);

	version(JsonLineNumbers){
		import dub.internal.vibecompat.core.log;
		int curline = line ? *line : 0;
	}

	switch( range.front ){
		case 'f':
			enforceJson(range[1 .. $].startsWith("alse"), "Expected 'false', got '"~range[0 .. min($, 5)]~"'.", filename, *line);
			range.popFrontN(5);
			ret = false;
			break;
		case 'n':
			enforceJson(range[1 .. $].startsWith("ull"), "Expected 'null', got '"~range[0 .. min($, 4)]~"'.", filename, *line);
			range.popFrontN(4);
			ret = null;
			break;
		case 't':
			enforceJson(range[1 .. $].startsWith("rue"), "Expected 'true', got '"~range[0 .. min($, 4)]~"'.", filename, *line);
			range.popFrontN(4);
			ret = true;
			break;
		case '0': .. case '9'+1:
		case '-':
			bool is_float;
			auto num = skipNumber(range, is_float, filename, *line);
			if( is_float ) ret = to!double(num);
			else ret = to!long(num);
			break;
		case '\"':
			ret = skipJsonString(range, filename, line);
			break;
		case '[':
			Json[] arr;
			range.popFront();
			while(true) {
				skipWhitespace(range, line);
				enforceJson(!range.empty, "Missing ']' before EOF.", filename, *line);
				if(range.front == ']') break;
				arr ~= parseJson(range, filename, line);
				skipWhitespace(range, line);
				enforceJson(!range.empty && (range.front == ',' || range.front == ']'), "Expected ']' or ','.", filename, *line);
				if( range.front == ']' ) break;
				else range.popFront();
			}
			range.popFront();
			ret = arr;
			break;
		case '{':
			Json[string] obj;
			range.popFront();
			while(true) {
				skipWhitespace(range, line);
				enforceJson(!range.empty, "Missing '}' before EOF.", filename, *line);
				if(range.front == '}') break;
				string key = skipJsonString(range, filename, line);
				skipWhitespace(range, line);
				enforceJson(range.startsWith(":"), "Expected ':' for key '" ~ key ~ "'", filename, *line);
				range.popFront();
				skipWhitespace(range, line);
				Json itm = parseJson(range, filename, line);
				obj[key] = itm;
				skipWhitespace(range, line);
				enforceJson(!range.empty && (range.front == ',' || range.front == '}'), "Expected '}' or ',' - got '"~range[0]~"'.", filename, *line);
				if( range.front == '}' ) break;
				else range.popFront();
			}
			range.popFront();
			ret = obj;
			break;
		default:
			enforceJson(false, "Expected valid json token, got '"~range[0 .. min($, 12)]~"'.", filename, *line);
	}

	assert(ret.type != Json.Type.undefined);
	version(JsonLineNumbers) ret.line = curline;
	return ret;
}

/**
	Parses the given JSON string and returns the corresponding Json object.

	Throws an Exception if any parsing error occurs.
*/
Json parseJsonString(string str, string filename = null)
{
	int line = 0;
	auto ret = parseJson(str, filename, &line);
	enforceJson(str.strip().length == 0, "Expected end of string after JSON value, not '"~str.strip()~"'.", filename, line);
	return ret;
}

unittest {
	assert(parseJsonString("null") == Json(null));
	assert(parseJsonString("true") == Json(true));
	assert(parseJsonString("false") == Json(false));
	assert(parseJsonString("1") == Json(1));
	assert(parseJsonString("2.0") == Json(2.0));
	assert(parseJsonString("\"test\"") == Json("test"));
	assert(parseJsonString("[1, 2, 3]") == Json([Json(1), Json(2), Json(3)]));
	assert(parseJsonString("{\"a\": 1}") == Json(["a": Json(1)]));
	assert(parseJsonString(`"\\\/\b\f\n\r\t\u1234"`).get!string == "\\/\b\f\n\r\t\u1234");
}


/**
	Serializes the given value to JSON.

	The following types of values are supported:

	$(DL
		$(DT Json)            $(DD Used as-is)
		$(DT null)            $(DD Converted to Json.Type.null_)
		$(DT bool)            $(DD Converted to Json.Type.bool_)
		$(DT float, double)   $(DD Converted to Json.Type.Double)
		$(DT short, ushort, int, uint, long, ulong) $(DD Converted to Json.Type.int_)
		$(DT string)          $(DD Converted to Json.Type.string)
		$(DT T[])             $(DD Converted to Json.Type.array)
		$(DT T[string])       $(DD Converted to Json.Type.object)
		$(DT struct)          $(DD Converted to Json.Type.object)
		$(DT class)           $(DD Converted to Json.Type.object or Json.Type.null_)
	)

	All entries of an array or an associative array, as well as all R/W properties and
	all public fields of a struct/class are recursively serialized using the same rules.

	Fields ending with an underscore will have the last underscore stripped in the
	serialized output. This makes it possible to use fields with D keywords as their name
	by simply appending an underscore.

	The following methods can be used to customize the serialization of structs/classes:

	---
	Json toJson() const;
	static T fromJson(Json src);

	string toString() const;
	static T fromString(string src);
	---

	The methods will have to be defined in pairs. The first pair that is implemented by
	the type will be used for serialization (i.e. toJson overrides toString).
*/
Json serializeToJson(T)(T value)
{
	alias TU = Unqual!T;
	static if( is(TU == Json) ) return value;
	else static if( is(TU == typeof(null)) ) return Json(null);
	else static if( is(TU == bool) ) return Json(value);
	else static if( is(TU == float) ) return Json(cast(double)value);
	else static if( is(TU == double) ) return Json(value);
	else static if( is(TU == DateTime) ) return Json(value.toISOExtString());
	else static if( is(TU == SysTime) ) return Json(value.toISOExtString());
	else static if( is(TU : long) ) return Json(cast(long)value);
	else static if( is(TU == string) ) return Json(value);
	else static if( isArray!T ){
		auto ret = new Json[value.length];
		foreach( i; 0 .. value.length )
			ret[i] = serializeToJson(value[i]);
		return Json(ret);
	} else static if( isAssociativeArray!TU ){
		Json[string] ret;
		foreach( string key, value; value )
			ret[key] = serializeToJson(value);
		return Json(ret);
	} else static if( isJsonSerializable!TU ){
		return value.toJson();
	} else static if( isStringSerializable!TU ){
		return Json(value.toString());
	} else static if( is(TU == struct) ){
		Json[string] ret;
		foreach( m; __traits(allMembers, T) ){
			static if( isRWField!(TU, m) ){
				auto mv = __traits(getMember, value, m);
				ret[underscoreStrip(m)] = serializeToJson(mv);
			}
		}
		return Json(ret);
	} else static if( is(TU == class) ){
		if( value is null ) return Json(null);
		Json[string] ret;
		foreach( m; __traits(allMembers, T) ){
			static if( isRWField!(TU, m) ){
				auto mv = __traits(getMember, value, m);
				ret[underscoreStrip(m)] = serializeToJson(mv);
			}
		}
		return Json(ret);
	} else static if( isPointer!TU ){
		if( value is null ) return Json(null);
		return serializeToJson(*value);
	} else {
		static assert(false, "Unsupported type '"~T.stringof~"' for JSON serialization.");
	}
}


/**
	Deserializes a JSON value into the destination variable.

	The same types as for serializeToJson() are supported and handled inversely.
*/
void deserializeJson(T)(ref T dst, Json src)
{
	dst = deserializeJson!T(src);
}
/// ditto
T deserializeJson(T)(Json src)
{
	static if( is(T == Json) ) return src;
	else static if( is(T == typeof(null)) ){ return null; }
	else static if( is(T == bool) ) return src.get!bool;
	else static if( is(T == float) ) return src.to!float;   // since doubles are frequently serialized without
	else static if( is(T == double) ) return src.to!double; // a decimal point, we allow conversions here
	else static if( is(T == DateTime) ) return DateTime.fromISOExtString(src.get!string);
	else static if( is(T == SysTime) ) return SysTime.fromISOExtString(src.get!string);
	else static if( is(T : long) ) return cast(T)src.get!long;
	else static if( is(T == string) ) return src.get!string;
	else static if( isArray!T ){
		alias TV = typeof(T.init[0]) ;
		auto dst = new Unqual!TV[src.length];
		foreach( size_t i, v; src )
			dst[i] = deserializeJson!(Unqual!TV)(v);
		return dst;
	} else static if( isAssociativeArray!T ){
		alias TV = typeof(T.init.values[0]) ;
		Unqual!TV[string] dst;
		foreach( string key, value; src )
			dst[key] = deserializeJson!(Unqual!TV)(value);
		return dst;
	} else static if( isJsonSerializable!T ){
		return T.fromJson(src);
	} else static if( isStringSerializable!T ){
		return T.fromString(src.get!string);
	} else static if( is(T == struct) ){
		T dst;
		foreach( m; __traits(allMembers, T) ){
			static if( isRWPlainField!(T, m) || isRWField!(T, m) ){
				alias TM = typeof(__traits(getMember, dst, m)) ;
				__traits(getMember, dst, m) = deserializeJson!TM(src[underscoreStrip(m)]);
			}
		}
		return dst;
	} else static if( is(T == class) ){
		if( src.type == Json.Type.null_ ) return null;
		auto dst = new T;
		foreach( m; __traits(allMembers, T) ){
			static if( isRWPlainField!(T, m) || isRWField!(T, m) ){
				alias TM = typeof(__traits(getMember, dst, m)) ;
				__traits(getMember, dst, m) = deserializeJson!TM(src[underscoreStrip(m)]);
			}
		}
		return dst;
	} else static if( isPointer!T ){
		if( src.type == Json.Type.null_ ) return null;
		alias TD = typeof(*T.init) ;
		dst = new TD;
		*dst = deserializeJson!TD(src);
		return dst;
	} else {
		static assert(false, "Unsupported type '"~T.stringof~"' for JSON serialization.");
	}
}

unittest {
	import std.stdio;
	static struct S { float a; double b; bool c; int d; string e; byte f; ubyte g; long h; ulong i; float[] j; }
	immutable S t = {1.5, -3.0, true, int.min, "Test", -128, 255, long.min, ulong.max, [1.1, 1.2, 1.3]};
	S u;
	deserializeJson(u, serializeToJson(t));
	assert(t.a == u.a);
	assert(t.b == u.b);
	assert(t.c == u.c);
	assert(t.d == u.d);
	assert(t.e == u.e);
	assert(t.f == u.f);
	assert(t.g == u.g);
	assert(t.h == u.h);
	assert(t.i == u.i);
	assert(t.j == u.j);
}

unittest {
	static class C {
		int a;
		private int _b;
		@property int b() const { return _b; }
		@property void b(int v) { _b = v; }

		@property int test() const { return 10; }

		void test2() {}
	}
	C c = new C;
	c.a = 1;
	c.b = 2;

	C d;
	deserializeJson(d, serializeToJson(c));
	assert(c.a == d.a);
	assert(c.b == d.b);
}


/**
	Writes the given JSON object as a JSON string into the destination range.

	This function will convert the given JSON value to a string without adding
	any white space between tokens (no newlines, no indentation and no padding).
	The output size is thus minizized, at the cost of bad human readability.

	Params:
		dst   = References the string output range to which the result is written.
		json  = Specifies the JSON value that is to be stringified.

	See_Also: Json.toString, writePrettyJsonString
*/
void writeJsonString(R)(ref R dst, in Json json)
//	if( isOutputRange!R && is(ElementEncodingType!R == char) )
{
	final switch( json.type ){
		case Json.Type.undefined: dst.put("undefined"); break;
		case Json.Type.null_: dst.put("null"); break;
		case Json.Type.bool_: dst.put(cast(bool)json ? "true" : "false"); break;
		case Json.Type.int_: formattedWrite(dst, "%d", json.get!long); break;
		case Json.Type.float_: formattedWrite(dst, "%.16g", json.get!double); break;
		case Json.Type.string:
			dst.put("\"");
			jsonEscape(dst, cast(string)json);
			dst.put("\"");
			break;
		case Json.Type.array:
			dst.put("[");
			bool first = true;
			foreach( ref const Json e; json ){
				if( e.type == Json.Type.undefined ) continue;
				if( !first ) dst.put(",");
				first = false;
				writeJsonString(dst, e);
			}
			dst.put("]");
			break;
		case Json.Type.object:
			dst.put("{");
			bool first = true;
			foreach( string k, ref const Json e; json ){
				if( e.type == Json.Type.undefined ) continue;
				if( !first ) dst.put(",");
				first = false;
				dst.put("\"");
				jsonEscape(dst, k);
				dst.put("\":");
				writeJsonString(dst, e);
			}
			dst.put("}");
			break;
	}
}

/**
	Writes the given JSON object as a prettified JSON string into the destination range.

	The output will contain newlines and indents to make the output human readable.

	Params:
		dst   = References the string output range to which the result is written.
		json  = Specifies the JSON value that is to be stringified.
		level = Specifies the base amount of indentation for the output. Indentation is always
			done using tab characters.

	See_Also: Json.toPrettyString, writeJsonString
*/
void writePrettyJsonString(R)(ref R dst, in Json json, int level = 0)
//	if( isOutputRange!R && is(ElementEncodingType!R == char) )
{
	final switch( json.type ){
		case Json.Type.undefined: dst.put("undefined"); break;
		case Json.Type.null_: dst.put("null"); break;
		case Json.Type.bool_: dst.put(cast(bool)json ? "true" : "false"); break;
		case Json.Type.int_: formattedWrite(dst, "%d", json.get!long); break;
		case Json.Type.float_: formattedWrite(dst, "%.16g", json.get!double); break;
		case Json.Type.string:
			dst.put("\"");
			jsonEscape(dst, cast(string)json);
			dst.put("\"");
			break;
		case Json.Type.array:
			dst.put("[");
			bool first = true;
			foreach( e; json ){
				if( e.type == Json.Type.undefined ) continue;
				if( !first ) dst.put(",");
				first = false;
				dst.put("\n");
				foreach( tab; 0 .. level+1 ) dst.put('\t');
				writePrettyJsonString(dst, e, level+1);
			}
			if( json.length > 0 ) {
				dst.put('\n');
				foreach( tab; 0 .. level ) dst.put('\t');
			}
			dst.put("]");
			break;
		case Json.Type.object:
			dst.put("{");
			bool first = true;
			foreach( string k, e; json ){
				if( e.type == Json.Type.undefined ) continue;
				if( !first ) dst.put(",");
				dst.put("\n");
				first = false;
				foreach( tab; 0 .. level+1 ) dst.put('\t');
				dst.put("\"");
				jsonEscape(dst, k);
				dst.put("\": ");
				writePrettyJsonString(dst, e, level+1);
			}
			if( json.length > 0 ) {
				dst.put('\n');
				foreach( tab; 0 .. level ) dst.put('\t');
			}
			dst.put("}");
			break;
	}
}

/// private
private void jsonEscape(R)(ref R dst, string s)
{
	foreach( ch; s ){
		switch(ch){
			default: dst.put(ch); break;
			case '\\': dst.put("\\\\"); break;
			case '\r': dst.put("\\r"); break;
			case '\n': dst.put("\\n"); break;
			case '\t': dst.put("\\t"); break;
			case '\"': dst.put("\\\""); break;
		}
	}
}

/// private
private string jsonUnescape(R)(ref R range)
{
	auto ret = appender!string();
	while(!range.empty){
		auto ch = range.front;
		switch( ch ){
			case '"': return ret.data;
			case '\\':
				range.popFront();
				enforce(!range.empty, "Unterminated string escape sequence.");
				switch(range.front){
					default: enforce(false, "Invalid string escape sequence."); break;
					case '"': ret.put('\"'); range.popFront(); break;
					case '\\': ret.put('\\'); range.popFront(); break;
					case '/': ret.put('/'); range.popFront(); break;
					case 'b': ret.put('\b'); range.popFront(); break;
					case 'f': ret.put('\f'); range.popFront(); break;
					case 'n': ret.put('\n'); range.popFront(); break;
					case 'r': ret.put('\r'); range.popFront(); break;
					case 't': ret.put('\t'); range.popFront(); break;
					case 'u':
						range.popFront();
						dchar uch = 0;
						foreach( i; 0 .. 4 ){
							uch *= 16;
							enforce(!range.empty, "Unicode sequence must be '\\uXXXX'.");
							auto dc = range.front;
							range.popFront();
							if( dc >= '0' && dc <= '9' ) uch += dc - '0';
							else if( dc >= 'a' && dc <= 'f' ) uch += dc - 'a' + 10;
							else if( dc >= 'A' && dc <= 'F' ) uch += dc - 'A' + 10;
							else enforce(false, "Unicode sequence must be '\\uXXXX'.");
						}
						ret.put(uch);
						break;
				}
				break;
			default:
				ret.put(ch);
				range.popFront();
				break;
		}
	}
	return ret.data;
}

private string skipNumber(ref string s, out bool is_float, string filename, int line)
{
	size_t idx = 0;
	is_float = false;
	if( s[idx] == '-' ) idx++;
	if( s[idx] == '0' ) idx++;
	else {
		enforceJson(isDigit(s[idx++]), "Digit expected at beginning of number.", filename, line);
		while( idx < s.length && isDigit(s[idx]) ) idx++;
	}

	if( idx < s.length && s[idx] == '.' ){
		idx++;
		is_float = true;
		while( idx < s.length && isDigit(s[idx]) ) idx++;
	}

	if( idx < s.length && (s[idx] == 'e' || s[idx] == 'E') ){
		idx++;
		is_float = true;
		if( idx < s.length && (s[idx] == '+' || s[idx] == '-') ) idx++;
		enforceJson(idx < s.length && isDigit(s[idx]), "Expected exponent." ~ s[0 .. idx], filename, line);
		idx++;
		while( idx < s.length && isDigit(s[idx]) ) idx++;
	}

	string ret = s[0 .. idx];
	s = s[idx .. $];
	return ret;
}

private string skipJsonString(ref string s, string filename, int* line = null)
{
	enforceJson(s.length >= 2, "Too small for a string: '" ~ s ~ "'", filename, *line);
	enforceJson(s[0] == '\"', "Expected string, not '" ~ s ~ "'", filename, *line);
	s = s[1 .. $];
	string ret = jsonUnescape(s);
	enforce(s.length > 0 && s[0] == '\"', "Unterminated string literal.", filename, *line);
	s = s[1 .. $];
	return ret;
}

private void skipWhitespace(ref string s, int* line = null)
{
	while( s.length > 0 ){
		switch( s[0] ){
			default: return;
			case ' ', '\t': s = s[1 .. $]; break;
			case '\n':
				s = s[1 .. $];
				if( s.length > 0 && s[0] == '\r' ) s = s[1 .. $];
				if( line ) (*line)++;
				break;
			case '\r':
				s = s[1 .. $];
				if( s.length > 0 && s[0] == '\n' ) s = s[1 .. $];
				if( line ) (*line)++;
				break;
		}
	}
}

/// private
private bool isDigit(T)(T ch){ return ch >= '0' && ch <= '9'; }

private string underscoreStrip(string field_name)
{
	if( field_name.length < 1 || field_name[$-1] != '_' ) return field_name;
	else return field_name[0 .. $-1];
}

private template isJsonSerializable(T) { enum isJsonSerializable = is(typeof(T.init.toJson()) == Json) && is(typeof(T.fromJson(Json())) == T); }
package template isStringSerializable(T) { enum isStringSerializable = is(typeof(T.init.toString()) == string) && is(typeof(T.fromString("")) == T); }

private void enforceJson(string filename = __FILE__, int line = __LINE__)(bool cond, lazy string message, string err_file, int err_line)
{
	if (!cond) {
		auto err_msg = format("%s(%s): Error: %s", err_file, err_line, message);
		throw new Exception(err_msg, filename, line);
	}
}
