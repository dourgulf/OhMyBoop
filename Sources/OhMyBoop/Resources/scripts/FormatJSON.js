/**
	{
		"api":1,
		"name":"Format JSON",
		"description":"Cleans and format JSON documents.",
		"author":"Ivan",
		"icon":"broom",
		"tags":"json,prettify,clean,indent"
	}
**/

function main(state) {
	try {
		// Keep native JSON parsing as the authority; diagnose only on failure.
		state.text = JSON.stringify(JSON.parse(state.text), null, 2);
	}
	catch(error) {
		var diagnostic = require('@boop/json-diagnostics').diagnose(state.text);
		state.postError(diagnostic ? diagnostic.message : String(error), diagnostic ? diagnostic.offset : null);
	}
	
	
}
