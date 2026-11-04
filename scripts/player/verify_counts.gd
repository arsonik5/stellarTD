extends Node

func count_functions():
	var lines := FileAccess.get_file_as_string("res://scripts/player/verify_counts.gd").split("\n")
	var func_lines := []
	
	for i in lines.size():
		if lines[i].strip().begins_with("func "):
			func_lines.append(i)
	
	return func_lines
