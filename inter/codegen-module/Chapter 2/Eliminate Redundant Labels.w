[CodeGen::Labels::] Eliminate Redundant Labels.

To remove labels which are defined but never jumped to.

@h Pipeline stage.
I7 tends to produce a lot of labels when compiling complicated text
substitutions, but many (around 2000 in a typical run) are never branched to,
either by a jump invocation or by assembly language.

These spurious labels cause no real problem except untidiness, but removing
them provides a simple example of how peephole optimisation can be performed
on the Inter functions in a repository.

=
void CodeGen::Labels::create_pipeline_stage(void) {
	CodeGen::Stage::new(I"eliminate-redundant-labels", CodeGen::Labels::run_pipeline_stage, NO_STAGE_ARG, FALSE);
}

int CodeGen::Labels::run_pipeline_stage(pipeline_step *step) {
	Inter::Tree::traverse(step->repository, CodeGen::Labels::visitor, NULL, NULL, 0);
	return TRUE;
}

void CodeGen::Labels::visitor(inter_tree *I, inter_tree_node *P, void *state) {
	if (P->W.data[ID_IFLD] == PACKAGE_IST) {
		inter_package *pack = Inter::Package::defined_by_frame(P);
		if (Inter::Packages::is_codelike(pack)) @<Perform peephole optimisation on this block@>;
	}
}

@h Peephole optimisation.
We can now forget about the larger package structure, and just look through
the peephole at a single function in Inter. It has its own symbols table, for
local variables and label names, and also has a tree of code to define what
it does.

@<Perform peephole optimisation on this block@> =
	inter_symbols_table *local_symbols = Inter::Packages::scope(pack);
	@<Mark all the labels for this function as being unused@>;
	@<Look through the function for mentions of labels, marking those as used@>;
	@<Remove the label declarations for any that are still marked unused@>;

@ The symbol flag |USED_MARK_BIT| is free for us to use, but its value for
any given symbol is undefined when we begin. We'll clear it for all labels.

@<Mark all the labels for this function as being unused@> =
	LOOP_OVER_SYMBOLS_TABLE(S, local_symbols)
		if (Inter::Symbols::is_label(S))
			Inter::Symbols::clear_flag(S, USED_MARK_BIT);

@<Look through the function for mentions of labels, marking those as used@> =
	inter_tree_node *D = Inter::Packages::definition(pack);
	CodeGen::Labels::traverse_code_tree(D);

@ Anything not marked used must be unused, so we can get rid of it. We do this
by striking its definition; the definition of a label symbol is the line
which shows where it belongs in the function (written |.Example| in Inter
syntax). Striking this does two things: it removes the definition line; and
it renders the symbol undefined. It still lives on in the function's symbols
table, though, and (since we have made sure there are no references to it from
anywhere) we may as well remove it.

@<Remove the label declarations for any that are still marked unused@> =
	LOOP_OVER_SYMBOLS_TABLE(S, local_symbols)
		if (Inter::Symbols::is_label(S))
			if (Inter::Symbols::get_flag(S, USED_MARK_BIT) == FALSE) {
				Inter::Symbols::strike_definition(S);
				Inter::Symbols::remove_from_table(S);
			}

@ The following visits every line of code in the function, in the same order
it would be written out in a listing.

=
void CodeGen::Labels::traverse_code_tree(inter_tree_node *P) {
	LOOP_THROUGH_INTER_CHILDREN(F, P) {
		@<Examine a line of code in the function@>;
		CodeGen::Labels::traverse_code_tree(F);
	}
}

@ If a label is used, there will be line reading |lab Example| or similar.
We look for such lines.

@<Examine a line of code in the function@> =
	if (F->W.data[ID_IFLD] == LAB_IST) {
		inter_symbol *lab = Inter::Lab::label_symbol(F);
		Inter::Symbols::set_flag(lab, USED_MARK_BIT);
	}