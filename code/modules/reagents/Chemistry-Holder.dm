

var/const/TOUCH = 1
var/const/INGEST = 2

///////////////////////////////////////////////////////////////////////////////////

/datum/reagents
	var/list/datum/reagent/reagent_list = new/list()
	var/list/amount_cache=list() //-- N3X
	var/total_volume = 0
	var/maximum_volume = 100
	var/atom/my_atom = null

/datum/reagents/New(maximum=100)
	maximum_volume = maximum

	//I dislike having these here but map-objects are initialised before world/New() is called. >_>
	if (!chemical_reagents_list)
		//Chemical Reagents - Initialises all /datum/reagent into a list indexed by reagent id
		chemical_reagents_list = list()

		for (var/path in typesof(/datum/reagent) - /datum/reagent)
			var/datum/reagent/D = new path()
			chemical_reagents_list[D.id] = D

	if (!chemical_reactions_list)
		//Chemical Reactions - Initialises all /datum/chemical_reaction into a list
		// It is filtered into multiple lists within a list.
		// For example:
		// chemical_reaction_list[PLASMA] is a list of all reactions relating to plasma

		chemical_reactions_list = list()

		for (var/path in typesof(/datum/chemical_reaction) - /datum/chemical_reaction)

			var/datum/chemical_reaction/D = new path()
			var/list/reaction_ids = list()

			if(D.required_reagents && D.required_reagents.len)
				for(var/reaction in D.required_reagents)
					reaction_ids += reaction

			// Create filters based on each reagent id in the required reagents list
			for(var/id in reaction_ids)
				if(!chemical_reactions_list[id])
					chemical_reactions_list[id] = list()
				chemical_reactions_list[id] += D
				break // Don't bother adding ourselves to other reagent ids, it is redundant.

/datum/reagents/proc/remove_any(var/amount=1)
	var/total_transfered = 0
	var/current_list_element = 1

	current_list_element = rand(1,reagent_list.len)

	while(total_transfered != amount)
		if(total_transfered >= amount)
			break
		if(is_empty() || !reagent_list.len)
			break

		if(current_list_element > reagent_list.len)
			current_list_element = 1
		var/datum/reagent/current_reagent = reagent_list[current_list_element]

		src.remove_reagent(current_reagent.id, 1)

		current_list_element++
		total_transfered++

		//src.update_total() // This is called from fucking remove_agent() -- N3X

	handle_reactions()
	return total_transfered

/datum/reagents/proc/get_master_reagent_name()
	var/the_name = null
	var/the_volume = 0
	for(var/datum/reagent/A in reagent_list)
		if(A.volume > the_volume)
			the_volume = A.volume
			the_name = A.name

	return the_name

/datum/reagents/proc/get_master_reagent_id()
	var/the_id = null
	var/the_volume = 0
	for(var/datum/reagent/A in reagent_list)
		if(A.volume > the_volume)
			the_volume = A.volume
			the_id = A.id

	return the_id

/* Transfers reagents from one reagents datum to another.
 * target: Can be either a specific reagents datum, or an atom (in which case the atom's respective reagent datum will be used)
 * amount: Desired amount to transfer. If the target doesn't have enough space, it will only transfer as much as possible rather than the full amount.
 * multiplier: Magically multiplies the amount of reagents that the target will receive (does not affect how much is removed from the source)
 * preserve_data: If false, the reagents data will be lost. Useful if you use data for some strange stuff and don't want it to be transferred.
 * log_transfer: If true, will log the transfer of these reagents to the chemistry investigation file. If the reagents transferred contain a logged reagent, it will also alert admins.
 * whodunnit: If available, the mob that directly caused this transfer. Used for logging.
 */
/datum/reagents/proc/trans_to(var/target, var/amount=1, var/multiplier=1, var/preserve_data=1, var/log_transfer = FALSE, var/mob/whodunnit)
	if (!target)
		return

	var/datum/reagents/R
	if (istype(target, /datum/reagents))
		R = target
	else
		var/atom/movable/AM = target
		if (!AM.reagents || src.is_empty())
			return
		else
			R = AM.reagents

	amount = min(min(amount, src.total_volume), R.maximum_volume-R.total_volume)
	var/part = amount / src.total_volume
	var/trans_data = null

	if(istype(R.my_atom, /obj))
		var/obj/O = R.my_atom
		if(!O.log_reagents)
			log_transfer = FALSE
	var/list/logged_message = list()
	var/list/adminwarn_message = list()

	for (var/datum/reagent/current_reagent in src.reagent_list)
		if (!current_reagent)
			continue
		if (current_reagent.id == BLOOD && iscarbon(target))
			var/mob/living/carbon/C = target
			C.inject_blood(my_atom, amount)
			continue
		var/current_reagent_transfer = current_reagent.volume * part
		if(preserve_data)
			trans_data = current_reagent.data
		if(log_transfer)
			logged_message += "[current_reagent_transfer]u of [current_reagent.name]"
			if(current_reagent.id in reagents_to_log)
				adminwarn_message += "[current_reagent_transfer]u of <span class='warning'>[current_reagent.name]</span>"

		R.add_reagent(current_reagent.id, (current_reagent_transfer * multiplier), trans_data)
		src.remove_reagent(current_reagent.id, current_reagent_transfer)

	// Called from add/remove_agent. -- N3X
	//src.update_total()
	//R.update_total()
	R.handle_reactions()
	src.handle_reactions()

	if(log_transfer && logged_message.len)
		var/turf/T = get_turf(my_atom)
		minimal_investigation_log(I_CHEMS, "[whodunnit ? "[key_name(whodunnit)]" : "(N/A, last user processed: [usr.ckey])"] \
		transferred [english_list(logged_message)] from \a [my_atom] \ref[my_atom] to \a [R.my_atom] \ref[R.my_atom].", prefix=" ([T.x],[T.y],[T.z])")
		if(adminwarn_message.len)
			message_admins("[whodunnit ? "[key_name_and_info(whodunnit)] " : "(unknown whodunnit, last whodunnit processed: [usr.ckey])"]\
			has transferred [english_list(adminwarn_message)] from \a [my_atom] (<A HREF='?_src_=vars;Vars=\ref[my_atom]'>VV</A>) to \a [R.my_atom] (<A HREF='?_src_=vars;Vars=\ref[R.my_atom]'>VV</A>).\
			[whodunnit ? " [formatJumpTo(whodunnit)]" : ""]")

	return amount

//I totally cannot tell why this proc exists
/datum/reagents/proc/trans_to_holder(var/datum/reagents/target, var/amount=1, var/multiplier=1, var/preserve_data=1)//if preserve_data=0, the reagents data will be lost. Usefull if you use data for some strange stuff and don't want it to be transferred.
	if (!target || src.is_empty())
		return
	var/datum/reagents/R = target
	amount = min(min(amount, src.total_volume), R.maximum_volume-R.total_volume)
	var/part = amount / src.total_volume
	var/trans_data = null
	for (var/datum/reagent/current_reagent in src.reagent_list)
		if (!current_reagent)
			continue
		var/current_reagent_transfer = current_reagent.volume * part
		if(preserve_data)
			trans_data = current_reagent.data

		R.add_reagent(current_reagent.id, (current_reagent_transfer * multiplier), trans_data)
		src.remove_reagent(current_reagent.id, current_reagent_transfer)

	// Called from add/remove_agent. -- N3X
	//src.update_total()
	//R.update_total()
	R.handle_reactions()
	src.handle_reactions()
	return amount
/*
trans_to_atmos(var/datum/gas_mixture/target, var/amount=1, var/multiplier=1, var/preserve_data=1)//if preserve_data=0, the reagents data will be lost. Usefull if you use data for some strange stuff and don't want it to be transferred.
	if (!target )
		return
	if (!target.aerosols || src.total_volume<=0)
		return
	var/datum/reagents/R = target.aerosols
	amount = min(min(amount, src.total_volume), R.maximum_volume-R.total_volume)
	var/part = amount / src.total_volume
	var/trans_data = null
	for (var/datum/reagent/current_reagent in src.reagent_list)
		if (!current_reagent)
			continue
		var/current_reagent_transfer = current_reagent.volume * part
		if(preserve_data)
			trans_data = current_reagent.data

		R.add_reagent(current_reagent.id, (current_reagent_transfer * multiplier), trans_data)
		src.remove_reagent(current_reagent.id, current_reagent_transfer)

	src.update_total()
	R.update_total()
	R.handle_reactions()
	src.handle_reactions()
	return amount
*/

//Pretty straightforward, remove from all of our chemicals at once, as if transfering to a nonexistant container or something.
/datum/reagents/proc/remove_all(var/amount=1)
	amount = min(amount, src.total_volume)
	var/part = amount / src.total_volume
	for (var/datum/reagent/current_reagent in src.reagent_list)
		if (!current_reagent)
			continue
		if(src.remove_reagent(current_reagent.id, current_reagent.volume * part))
			. = 1 //We removed SOMETHING.
	src.handle_reactions()

/datum/reagents/proc/copy_to(var/obj/target, var/amount=1, var/multiplier=1, var/preserve_data=1)
	if(!target)
		return
	if(!target.reagents || src.is_empty())
		return
	var/datum/reagents/R = target.reagents
	amount = min(min(amount, src.total_volume), R.maximum_volume-R.total_volume)
	var/part = amount / src.total_volume
	var/trans_data = null
	for (var/datum/reagent/current_reagent in src.reagent_list)
		var/current_reagent_transfer = current_reagent.volume * part
		if(preserve_data)
			trans_data = current_reagent.data
		R.add_reagent(current_reagent.id, (current_reagent_transfer * multiplier), trans_data)

	// Called from add/remove_agent. -- N3X
	//src.update_total()
	//R.update_total()
	R.handle_reactions()
	src.handle_reactions()
	return amount

/datum/reagents/proc/trans_id_to(var/obj/target, var/reagent, var/amount=1, var/preserve_data=1)//Not sure why this proc didn't exist before. It does now! /N
	if (!target)
		return
	if (!target.reagents || src.is_empty() || !src.get_reagent_amount(reagent))
		return

	var/datum/reagents/R = target.reagents
	if(src.get_reagent_amount(reagent)<amount)
		amount = src.get_reagent_amount(reagent)
	amount = min(amount, R.maximum_volume-R.total_volume)
	var/trans_data = null
	for (var/datum/reagent/current_reagent in src.reagent_list)
		if(current_reagent.id == reagent)
			if(preserve_data)
				trans_data = current_reagent.data
			R.add_reagent(current_reagent.id, amount, trans_data)
			src.remove_reagent(current_reagent.id, amount, 1)
			break

	// Called from add/remove_agent. -- N3X
	//src.update_total()
	//R.update_total()
	R.handle_reactions()
	//src.handle_reactions() Don't need to handle reactions on the source since you're (presumably isolating and) transferring a specific reagent.
	return amount

/*
	if (!target)
		return
	var/total_transfered = 0
	var/current_list_element = 1
	var/datum/reagents/R = target.reagents
	var/trans_data = null
	//if(R.total_volume + amount > R.maximum_volume) return 0

	current_list_element = rand(1,reagent_list.len) //Eh, bandaid fix.

	while(total_transfered != amount)
		if(total_transfered >= amount)
			break //Better safe than sorry.
		if(total_volume <= 0 || !reagent_list.len)
			break
		if(R.total_volume >= R.maximum_volume)
			break

		if(current_list_element > reagent_list.len)
			current_list_element = 1
		var/datum/reagent/current_reagent = reagent_list[current_list_element]
		if(preserve_data)
			trans_data = current_reagent.data
		R.add_reagent(current_reagent.id, (1 * multiplier), trans_data)
		src.remove_reagent(current_reagent.id, 1)

		current_list_element++
		total_transfered++

	// Called from add/remove_agent. -- N3X
	//src.update_total()
	//R.update_total()
	R.handle_reactions()
	handle_reactions()

	return total_transfered
*/

/datum/reagents/proc/metabolize(var/mob/M, var/alien)
	for(var/A in reagent_list)
		var/datum/reagent/R = A
		if(M && R)
			R.on_mob_life(M, alien)
			R.metabolize(M)
	update_total()

/datum/reagents/proc/update_aerosol(var/mob/M)
	for(var/A in reagent_list)
		var/datum/reagent/R = A
		if(M && R)
			R.on_mob_life(M)
	update_total()

/datum/reagents/proc/conditional_update_move(var/atom/A, var/Running = 0)
	for(var/datum/reagent/R in reagent_list)
		R.on_move (A, Running)
	update_total()

/datum/reagents/proc/conditional_update(var/atom/A, )
	for(var/datum/reagent/R in reagent_list)
		R.on_update (A)
	update_total()

/datum/reagents/proc/handle_reactions()
	if(!my_atom)
		return //sanity check
	if(my_atom.flags & NOREACT)
		return //Yup, no reactions here. No siree.

	var/reaction_occured = 0
	do
		reaction_occured = 0
		for(var/datum/reagent/R in reagent_list) // Usually a small list
			for(var/reaction in chemical_reactions_list[R.id]) // Was a big list but now it should be smaller since we filtered it with our reagent id

				if(!reaction)
					continue

				var/datum/chemical_reaction/C = reaction

				//check if this recipe needs to be heated to mix
				if(C.requires_heating)
					if(istype(my_atom.loc, /obj/machinery/bunsen_burner))
						if(!my_atom.loc:heated)
							continue
					else
						continue

				var/total_required_reagents = C.required_reagents.len
				var/total_matching_reagents = 0
				var/total_required_catalysts = C.required_catalysts.len
				var/total_matching_catalysts= 0
				var/matching_container = 0
				var/matching_other = 0
				var/list/multipliers = new/list()

				for(var/B in C.required_reagents)
					if(!has_reagent(B, C.required_reagents[B]))
						break
					total_matching_reagents++
					multipliers += round(get_reagent_amount(B) / C.required_reagents[B])
				for(var/B in C.required_catalysts)
					if(!has_reagent(B, C.required_catalysts[B]))
						break
					total_matching_catalysts++

				if(!C.required_container)
					matching_container = 1

				else
					if(my_atom.type == C.required_container)
						matching_container = 1

				if(!C.required_other)
					matching_other = 1

				else
					/*if(istype(my_atom, /obj/item/slime_core))
						var/obj/item/slime_core/M = my_atom

						if(M.POWERFLAG == C.required_other && M.Uses > 0) // added a limit to slime cores -- Muskets requested this
							matching_other = 1*/
					if(istype(my_atom, /obj/item/slime_extract))
						var/obj/item/slime_extract/M = my_atom

						if(M.Uses > 0) // added a limit to slime cores -- Muskets requested this
							matching_other = 1

				if(total_matching_reagents == total_required_reagents && total_matching_catalysts == total_required_catalysts && matching_container && matching_other)
					var/multiplier = min(multipliers)
					var/preserved_data = null
					for(var/B in C.required_reagents)
						if(!preserved_data)
							preserved_data = get_data(B)
						remove_reagent(B, (multiplier * C.required_reagents[B]), safety = 1)

					var/created_volume = C.result_amount*multiplier
					if(C.result)
						feedback_add_details("chemical_reaction","[C.result][created_volume]")
						multiplier = max(multiplier, 1) //this shouldnt happen ...
						add_reagent(C.result, created_volume)
						set_data(C.result, preserved_data)

						//add secondary products
						for(var/S in C.secondary_results)
							add_reagent(S, C.result_amount * C.secondary_results[S] * multiplier)

					if	(istype(my_atom, /obj/item/weapon/grenade/chem_grenade))
						my_atom.visible_message("<span class='caution'>[bicon(my_atom)] Something comes out of \the [my_atom].</span>")
						//Logging inside chem_grenade.dm, prime()
					else if	(istype(my_atom, /mob/living/carbon/human))
						my_atom.visible_message("<span class='notice'>[my_atom] shudders a little.</span>","<span class='notice'>You shudder a little.</span>")
						//Since the are no fingerprints to be had here, we'll trust the attack logs to log this
					else
						my_atom.visible_message("<span class='notice'>[bicon(my_atom)] The solution begins to bubble.</span>")
						C.log_reaction(src, created_volume)

					if(istype(my_atom, /obj/item/slime_extract))
						var/obj/item/slime_extract/ME2 = my_atom
						ME2.Uses--
						if(ME2.Uses <= 0) // give the notification that the slime core is dead
							if (!istype(ME2.loc, /obj/item/weapon/grenade/chem_grenade))
								ME2.visible_message("<span class='notice'>[bicon(my_atom)] \The [my_atom]'s power is consumed in the reaction.</span>")
							ME2.name = "used slime extract"
							ME2.desc = "This extract has been used up."

					playsound(get_turf(my_atom), 'sound/effects/bubbles.ogg', 80, 1)

					C.on_reaction(src, created_volume)
					reaction_occured = 1
					break

	while(reaction_occured)
	update_total()
	return 0

/datum/reagents/proc/isolate_reagent(var/reagent)
	for(var/A in reagent_list)
		var/datum/reagent/R = A
		if (R.id != reagent)
			del_reagent(R.id,update_totals=0)
	// Only call ONCE. -- N3X
	update_total()
	my_atom.on_reagent_change()

/datum/reagents/proc/del_reagent(var/reagent, var/update_totals=1)
	var/total_dirty=0
	for(var/A in reagent_list)
		var/datum/reagent/R = A
		if (R.id == reagent)
			R.reagent_deleted()
			reagent_list -= A
			R.holder = null
			total_dirty=1
			break

	if(total_dirty && update_totals)
		update_total()
		my_atom.on_reagent_change()
	return total_dirty

/datum/reagents/proc/update_total()
	total_volume = 0
	amount_cache.len = 0
	for(var/datum/reagent/R in reagent_list)
		if(R.volume < R.custom_metabolism/2) //Used to be 0.1, changing this to custom_metabolism/2 to alter balance as little as possible since the default metabolism is 0.2
			del_reagent(R.id,update_totals=0)
		else
			total_volume += R.volume
			amount_cache += list(R.id = R.volume)
	return 0

/datum/reagents/proc/clear_reagents()
	amount_cache.len = 0
	for(var/datum/reagent/R in reagent_list)
		del_reagent(R.id,update_totals=0)
	// Only call ONCE. -- N3X
	update_total()
	if(my_atom)
		my_atom.on_reagent_change()
	return 0

/datum/reagents/proc/reaction(var/atom/A, var/method=TOUCH, var/volume_modifier=0)

	switch(method)
		if(TOUCH)
			for(var/datum/reagent/R in reagent_list)
				if(ismob(A))
					if(isanimal(A))
						R.reaction_animal(A, TOUCH, R.volume+volume_modifier)
					else
						R.reaction_mob(A, TOUCH, R.volume+volume_modifier)
				if(isturf(A))
					R.reaction_turf(A, R.volume+volume_modifier)
				if(isobj(A))
					R.reaction_obj(A, R.volume+volume_modifier)
		if(INGEST)
			for(var/datum/reagent/R in reagent_list)
				if(ismob(A))
					if(isanimal(A))
						R.reaction_animal(A, INGEST, R.volume+volume_modifier)
					else
						R.reaction_mob(A, INGEST, R.volume+volume_modifier)
				if(isturf(A) && R)
					R.reaction_turf(A, R.volume+volume_modifier)
				if(isobj(A) && R)
					R.reaction_obj(A, R.volume+volume_modifier)
	return

/datum/reagents/proc/add_reagent(var/reagent, var/amount, var/list/data=null)
	if(!my_atom)
		return 0
	if(!isnum(amount))
		return 1
	update_total()
	if(total_volume + amount > maximum_volume)
		amount = (maximum_volume - total_volume) //Doesnt fit in. Make it disappear. Shouldn't happen. Will happen.

	for (var/datum/reagent/R in reagent_list)
		if (R.id == reagent)
			R.volume += amount
			update_total()
			my_atom.on_reagent_change()

			if(!isnull(data))
				if (reagent == BLOOD)
				//to do: add better ways for blood colors to interact with each other
				//right now we don't support blood mixing or something similar at all.
					if(R.data["virus2"] && data["virus2"])
						R.data["virus2"] |= virus_copylist(data["virus2"])
				else
					R.data = data //just in case someone adds a new reagent with a data var

			handle_reactions()
			return 0

	var/datum/reagent/D = chemical_reagents_list[reagent]
	if(D)

		var/datum/reagent/R = new D.type()
		reagent_list += R
		R.holder = src
		R.volume = amount

		if(!isnull(data))
			if (reagent == BLOOD)
				R.data = data.Copy()
				if(data["virus2"])
					R.data["virus2"] |= virus_copylist(data["virus2"])
				if(data["blood_colour"])
					R.color = data["blood_colour"]
			else
				R.data = data

		update_total()
		my_atom.on_reagent_change()
		handle_reactions()
		return 0
	else
		warning("[my_atom] attempted to add a reagent called '[reagent]' which doesn't exist. ([usr])")

	handle_reactions()

	return 1

/datum/reagents/proc/remove_reagent(var/reagent, var/amount, var/safety)//Added a safety check for the trans_id_to

	if(!isnum(amount))
		return 1

	for (var/datum/reagent/R in reagent_list)
		if (R.id == reagent)
			if(!R.on_removal(amount))
				return 0 //handled and reagent says fuck no
			R.volume -= amount
			update_total()
			if(!safety)//So it does not handle reactions when it need not to
				handle_reactions()
			if(my_atom)
				my_atom.on_reagent_change()
			return 0

	return 1

/**************************************
 *  RETURNS A BOOL NOW, USE get_reagent IF YOU NEED TO GET ONE.
 **************************************/
/datum/reagents/proc/has_reagent(var/reagent, var/amount = -1)
	// N3X: Caching shit.
	// Only cache if not using get (since we only track bools)
	if(reagent in amount_cache)
		return amount_cache[reagent] >= max(0,amount)
	return 0

/datum/reagents/proc/has_any_reagents(var/list/input_reagents, var/amount = -1)		//returns true if any of the input reagents are found
	. = FALSE
	for(var/i in input_reagents)
		if(has_reagent(i, amount))
			return TRUE

/datum/reagents/proc/has_all_reagents(var/list/input_reagents, var/amount = -1)		//returns true if all of the input reagents are found
	for(var/i in input_reagents)
		if(!has_reagent(i, amount))
			return FALSE
	return TRUE

/datum/reagents/proc/get_reagent(var/reagent, var/amount = -1)
	// SLOWWWWWWW
	for(var/A in reagent_list)
		var/datum/reagent/R = A
		if (R.id == reagent)
			if(!amount)
				return R
			else
				if(R.volume >= amount)
					return R
			return 0
	return 0

/datum/reagents/proc/get_reagent_amount(var/reagent)
	for(var/A in reagent_list)
		var/datum/reagent/R = A
		if (R.id == reagent)
			return R.volume

	return 0

/datum/reagents/proc/get_reagents()
	var/res = ""
	for(var/datum/reagent/A in reagent_list)
		if (res != "")
			res += ","
		res += A.name

	return res

// Admin logging.
/datum/reagents/proc/get_reagent_ids(var/and_amount=0)
	var/list/stuff = list()
	for(var/datum/reagent/A in reagent_list)
		if(and_amount)
			stuff += "[get_reagent_amount(A.id)]u of [A.id]"
		else
			stuff += A.id
	return english_list(stuff, "no reagents")

/datum/reagents/proc/remove_all_type(var/reagent_type, var/amount, var/strict = 0, var/safety = 1) // Removes all reagent of X type. @strict set to 1 determines whether the childs of the type are included.
	if(!isnum(amount))
		return 1

	var/has_removed_reagent = 0

	for(var/datum/reagent/R in reagent_list)
		var/matches = 0
		// Switch between how we check the reagent type
		if(strict)
			if(R.type == reagent_type)
				matches = 1
		else
			if(istype(R, reagent_type))
				matches = 1
		// We found a match, proceed to remove the reagent.	Keep looping, we might find other reagents of the same type.
		if(matches)
			// Have our other proc handle removement
			has_removed_reagent = remove_reagent(R.id, amount, safety)

	return has_removed_reagent

//two helper functions to preserve data across reactions (needed for xenoarch)
/datum/reagents/proc/get_data(var/reagent_id)
	for(var/datum/reagent/D in reagent_list)
		if(D.id == reagent_id)
//						to_chat(world, "proffering a data-carrying reagent ([reagent_id])")
			return D.data

/datum/reagents/proc/set_data(var/reagent_id, var/new_data)
	for(var/datum/reagent/D in reagent_list)
		if(D.id == reagent_id)
//						to_chat(world, "reagent data set ([reagent_id])")
			D.data = new_data

/datum/reagents/Destroy()
	for(var/datum/reagent/reagent in reagent_list)
		qdel(reagent)

	reagent_list.Cut()

	if(my_atom)
		my_atom = null

/**
 * Helper proc to retrieve the 'bad' reagents in the holder. Used for logging.
 * Example of result: "5u of Polytrinic Acid, 5u of Cyanide, and 15u of Mindbreaker Toxin"
 */
/datum/reagents/proc/write_logged_reagents()
	. = list()

	for(var/datum/reagent/R in reagent_list)
		if(R.id in reagents_to_log) //reagents_to_log being a global list in objs.dm
			. += "[R.volume]u of [R.name]"

	return english_list(., nothing_text = "")

/datum/reagents/proc/log_bad_reagents(var/mob/user, var/atom/A)
	var/badreagents = write_logged_reagents()
	if(badreagents)
		add_gamelogs(user, "used \a [A] containing [badreagents]", admin = TRUE, tp_link = TRUE)

/datum/reagents/proc/is_empty()
	return total_volume <= 0

/datum/reagents/proc/is_full()
	return total_volume >= maximum_volume
///////////////////////////////////////////////////////////////////////////////////


/*
 * Convenience proc to create a reagents holder for an atom
 * max_vol is maximum volume of holder
 */
/atom/proc/create_reagents(const/max_vol)
	reagents = new/datum/reagents(max_vol)
	reagents.my_atom = src

/datum/reagents/send_to_past(var/duration)
	var/static/list/resettable_vars = list(
		"being_sent_to_past",
		"reagent_list",
		"amount_cache",
		"total_volume",
		"maximum_volume",
		"my_atom",
		"gcDestroyed")

	reset_vars_after_duration(resettable_vars, duration, TRUE)

	for(var/y in reagent_list)
		var/datum/reagent/R = y
		R.send_to_past(duration)

	spawn(duration + 1)
		if(my_atom)
			var/atom/A = my_atom
			A.reagents = src
