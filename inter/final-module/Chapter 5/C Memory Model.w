[CMemoryModel::] C Memory Model.

How arrays of all kinds are stored in C.

@h Setting up the model.

=
void CMemoryModel::initialise(code_generation_target *cgt) {
	METHOD_ADD(cgt, BEGIN_ARRAY_MTID, CMemoryModel::begin_array);
	METHOD_ADD(cgt, ARRAY_ENTRY_MTID, CMemoryModel::array_entry);
	METHOD_ADD(cgt, ARRAY_ENTRIES_MTID, CMemoryModel::array_entries);
	METHOD_ADD(cgt, END_ARRAY_MTID, CMemoryModel::end_array);
}

typedef struct C_generation_memory_model_data {
	int himem; /* high point of memory: 1 more than the largest legal address */
	struct text_stream *array_name;
	int entry_count;
	int next_node_is_a_ref;
} C_generation_memory_model_data;

void CMemoryModel::initialise_data(code_generation *gen) {
	C_GEN_DATA(memdata.himem) = 0;
	C_GEN_DATA(memdata.array_name) = Str::new();
	C_GEN_DATA(memdata.entry_count) = 0;
	C_GEN_DATA(memdata.next_node_is_a_ref) = FALSE;
}

@h Byte-addressable memory.
The Inter semantics require that there be an area of byte-accessible memory:

(a) Byte-accessible memory must contain all of the arrays. These can but need
not have alignment gaps in between them. (For C, they do not.)
(b) "Addresses" in this memory identify individual byte positions in it. These
can but need not start at 0. (For C, they do.) They must not be too large to
fit into an Inter value.
(c) When an array name is compiled, its runtime value must be its address.
(d) When an Inter value is stored in byte-accessible memory, it occupies either
2 or 4 consecutive bytes, with the little end first. The result is called a
"word". (For C, always 4, which is always |sizeof(i7val)|.) Conversion between
a word stored in memory and an Inter value must be faithful in both directions.
(e) Words can be stored at any byte position, and not only at (say) multiples
of 2 or 4.
(f) Arrays in memory are free to contain a mixture of bytes and words: some do.
(g) Data may be written in byte form and read back in word form, or vice versa.

We will manage that with a single C array. This is first predeclared here:

= (text to inform7_clib.h)
i7byte i7mem[];
=

@ Declaring that array is our main task in this section.

=
void CMemoryModel::begin(code_generation *gen) {
	generated_segment *saved = CodeGen::select(gen, c_mem_I7CGS);
	text_stream *OUT = CodeGen::current(gen);
	WRITE("i7byte i7mem[] = {\n");
	CodeGen::deselect(gen, saved);
}

@ We will end the array with two dummy bytes (which should never be accessed)
just in case, and to ensure that it is never empty, which would be illegal
in C.

=
void CMemoryModel::end(code_generation *gen) {
	generated_segment *saved = CodeGen::select(gen, c_mem_I7CGS);
	text_stream *OUT = CodeGen::current(gen);
	WRITE("0, 0 };\n");
	CodeGen::deselect(gen, saved);
}

@h Reading and writing memory.
Given the above array, it's easy to read and write bytes: if |a| is the address
then we can simply refer to |i7mem[a]|. Words are more challenging since we
need to pack and unpack them.

The following function reads a word which is in entry |array_index| (counting
0, 1, 2, ...) in the array which begins at the byte address |array_address| in
the bank of memory |data|. In practice, we will only every use this function
with |data| set to |i7mem|.

The equivalent for reading a byte entry is |data[array_address + array_index]|.

= (text to inform7_clib.h)
i7val i7_read_word(i7byte data[], i7val array_address, i7val array_index) {
	int byte_position = array_address + 4*array_index;
	return             (i7val) data[byte_position]      +
	            0x100*((i7val) data[byte_position + 1]) +
		      0x10000*((i7val) data[byte_position + 2]) +
		    0x1000000*((i7val) data[byte_position + 3]);
}
=

@ Packing, unlike unpacking, is done with macros so that it is possible to
express a packed word in constant context, which we will need later.

= (text to inform7_clib.h)
#define I7BYTE_3(V) ((V & 0xFF000000) >> 24)
#define I7BYTE_2(V) ((V & 0x00FF0000) >> 16)
#define I7BYTE_1(V) ((V & 0x0000FF00) >> 8)
#define I7BYTE_0(V)  (V & 0x000000FF)

i7val i7_write_word(i7byte data[], i7val array_address, i7val array_index, i7val new_val, int way) {
	i7val old_val = i7_read_word(data, array_address, array_index);
	i7val return_val = new_val;
	switch (way) {
		case i7_lvalue_PREDEC:   return_val = old_val;   new_val = old_val-1; break;
		case i7_lvalue_POSTDEC:  return_val = old_val-1; new_val = old_val-1; break;
		case i7_lvalue_PREINC:   return_val = old_val;   new_val = old_val+1; break;
		case i7_lvalue_POSTINC:  return_val = old_val+1; new_val = old_val+1; break;
		case i7_lvalue_SETBIT:   new_val = old_val | new_val; return_val = new_val; break;
		case i7_lvalue_CLEARBIT: new_val = old_val &(~new_val); return_val = new_val; break;
	}
	int byte_position = array_address + 4*array_index;
	data[byte_position]   = I7BYTE_0(new_val);
	data[byte_position+1] = I7BYTE_1(new_val);
	data[byte_position+2] = I7BYTE_2(new_val);
	data[byte_position+3] = I7BYTE_3(new_val);
	return return_val;
}
=

@h Populating memory with arrays.
Inter supports four sorts of arrays, with behaviour as laid out in this 2x2 grid:
= (text)
			 | entries count 0, 1, 2,...	 | entry 0 is N, then entries count 1, 2, ..., N
-------------+-------------------------------+-----------------------------------------------
byte entries | BYTE_ARRAY_FORMAT             | BUFFER_ARRAY_FORMAT
-------------+-------------------------------+-----------------------------------------------
word entries | WORD_ARRAY_FORMAT             | TABLE_ARRAY_FORMAT
-------------+-------------------------------+-----------------------------------------------
=

=
void CMemoryModel::begin_array(code_generation_target *cgt, code_generation *gen,
	text_stream *array_name, int format) {
	Str::clear(C_GEN_DATA(memdata.array_name));
	WRITE_TO(C_GEN_DATA(memdata.array_name), "%S", array_name);
	C_GEN_DATA(memdata.entry_count) = 0;

	text_stream *format_name = I"unknown";
	@<Work out the format name@>;
	@<Define a constant for the byte address in memory where the array begins@>;
	if ((format == TABLE_ARRAY_FORMAT) || (format == BUFFER_ARRAY_FORMAT))
		@<Place the extent entry N at index 0@>;
}

@<Work out the format name@> =
	switch (format) {
		case BYTE_ARRAY_FORMAT: format_name = I"byte"; break;
		case WORD_ARRAY_FORMAT: format_name = I"word"; break;
		case BUFFER_ARRAY_FORMAT: format_name = I"buffer"; break;
		case TABLE_ARRAY_FORMAT: format_name = I"table"; break;
	}

@ Crucially, the array names are |#define| constants declared up at the top
of the source code: they are not variables with pointer types, or something
like that. This means they can legally be used as values elsewhere in |i7mem|,
or as initial values of variables, and so on.

Object, class and function names can also legally appear as array entries,
because they too are defined constants, equal to their IDs: see //C Object Model//.

@<Define a constant for the byte address in memory where the array begins@> =
	generated_segment *saved = CodeGen::select(gen, c_predeclarations_I7CGS);
	text_stream *OUT = CodeGen::current(gen);
	WRITE("#define ");
	CNamespace::mangle(cgt, OUT, array_name);
	WRITE(" %d /* = position in i7mem of %S array %S */\n",
		C_GEN_DATA(memdata.himem), format_name, array_name);
	CodeGen::deselect(gen, saved);

@ Of course, right now we don't know |N|, the extent of the array. So we will
refer to this with a constant like |xt_myarray|, which we will retrospectively
predefine when the array ends.

@<Place the extent entry N at index 0@> =
	TEMPORARY_TEXT(extname)
	WRITE_TO(extname, "xt_%S", array_name);
	CMemoryModel::array_entry(cgt, gen, extname, format);
	DISCARD_TEXT(extname)

@ The call to |CMemoryModel::begin_array| is then followed by a series of calls to:

=
void CMemoryModel::array_entry(code_generation_target *cgt, code_generation *gen,
	text_stream *entry, int format) {
	generated_segment *saved = CodeGen::select(gen, c_mem_I7CGS);
	text_stream *OUT = CodeGen::current(gen);
	if ((format == TABLE_ARRAY_FORMAT) || (format == WORD_ARRAY_FORMAT))
		@<This is a word entry@>
	else
		@<This is a byte entry@>;
	CodeGen::deselect(gen, saved);
	C_GEN_DATA(memdata.entry_count)++;
}

@<This is a byte entry@> =
	WRITE("    (i7byte) %S, /* %d */\n", entry, C_GEN_DATA(memdata.himem));
	C_GEN_DATA(memdata.himem) += 1;

@ Now we see why it was important for |I7BYTE_0| and so on to be macros: they
use only arithmetic operations which can be constant-folded by the C compiler,
and therefore if |X| is a valid constant-context expression in C then so is
|I7BYTE_0(X)|.

@<This is a word entry@> =
	WRITE("    I7BYTE_0(%S), I7BYTE_1(%S), I7BYTE_2(%S), I7BYTE_3(%S), /* %d */\n",
		entry, entry, entry, entry, C_GEN_DATA(memdata.himem));
	C_GEN_DATA(memdata.himem) += 4;

@ Alternatively, we can just specify how many entries there will be: they will
then be initialised to 0.

=
void CMemoryModel::array_entries(code_generation_target *cgt, code_generation *gen,
	int how_many, int plus_ips, int format) {
	if (plus_ips) how_many += 64;
	for (int i=0; i<how_many; i++) CMemoryModel::array_entry(cgt, gen, I"0", format);
}

@ When all the entries have been placed, the following is called. It does nothing
except to predeclare the extent constant, if one was used.

=
void CMemoryModel::end_array(code_generation_target *cgt, code_generation *gen, int format) {
	if ((format == TABLE_ARRAY_FORMAT) || (format == BUFFER_ARRAY_FORMAT)) {
		generated_segment *saved = CodeGen::select(gen, c_predeclarations_I7CGS);
		text_stream *OUT = CodeGen::current(gen);
		WRITE("#define xt_%S %d\n",
			C_GEN_DATA(memdata.array_name), C_GEN_DATA(memdata.entry_count)-1);
		CodeGen::deselect(gen, saved);
	}
}

@h Primitives for byte and word lookup.
The signatures here are:

= (text)
primitive !lookup val val -> val
primitive !lookupbyte val val -> val
=

=
int CMemoryModel::handle_store_by_ref(code_generation *gen, inter_tree_node *ref) {
	if (CodeGen::CL::node_is_ref_to(gen->from, ref, LOOKUP_BIP)) return TRUE;
	return FALSE;
}

int CMemoryModel::compile_primitive(code_generation *gen, inter_ti bip, inter_tree_node *P) {
	text_stream *OUT = CodeGen::current(gen);
	switch (bip) {
		case LOOKUP_BIP:     if (CReferences::am_I_a_ref(gen)) @<Word value as reference@>
						     else @<Word value as value@>;
						     break;
		case LOOKUPBYTE_BIP: @<Byte value as value@>; break;
		default:             return NOT_APPLICABLE;
	}
	return FALSE;
}

@<Word value as value@> =
	WRITE("i7_read_word(i7mem, "); INV_A1; WRITE(", "); INV_A2; WRITE(")");

@<Word value as reference@> =
	WRITE("i7_write_word(i7mem, "); INV_A1; WRITE(", "); INV_A2; WRITE(", ");
	
@<Byte value as value@> =
	WRITE("i7mem["); INV_A1; WRITE(" + "); INV_A2; WRITE("]");