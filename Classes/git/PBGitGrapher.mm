//
//  PBGitGrapher.m
//  GitX
//
//  Created by Pieter de Bie on 17-06-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBGitGrapher.h"
#import "PBGitCommit.h"
#import "PBGitLane.h"
#import "PBGitGraphLine.h"

#import <vector>
#import <git2/oid.h>
#include <algorithm>

using namespace std;
typedef std::vector<PBGitLane *> LaneCollection;


@implementation PBGitGrapher

- (id) initWithRepository: (PBGitRepository*) repo
{
	pl = new LaneCollection;

	PBGitLane::resetColors();
	return self;
}

void add_line(struct PBGitGraphLine *lines, int *nLines, int upper, int from, int to, int index)
{
	// TODO: put in one thing
	struct PBGitGraphLine a = { upper, from, to, index };
	lines[(*nLines)++] = a;
}

- (void) decorateCommit: (PBGitCommit *) commit
{
	int i = 0, newPos = -1;
	LaneCollection *currentLanes = new LaneCollection;
	LaneCollection *previousLanes = (LaneCollection *)pl;
	NSArray *parents = [commit parents];
	int nParents = [parents count];

	int maxLines = (previousLanes->size() + nParents + 2) * 2;
	struct PBGitGraphLine *lines = (struct PBGitGraphLine *)malloc(sizeof(struct PBGitGraphLine) * maxLines);
	int currentLine = 0;

	PBGitLane *currentLane = NULL;
	BOOL didFirst = NO;
	git_oid commit_oid = [[commit sha] oid];
	
	// First, iterate over earlier columns and pass through any that don't want this commit
	if (previous != nil) {
		// We can't count until numColumns here, as it's only used for the width of the cell.
		LaneCollection::iterator it = previousLanes->begin();
		for (; it != previousLanes->end(); ++it) {
			i++;
			if (!*it) // This is an empty lane, created when the lane previously had a parentless(root) commit
				continue;

			// This is our commit! We should do a "merge": move the line from
			// our upperMapping to their lowerMapping
			if ((*it)->isCommit(commit_oid)) {
				if (!didFirst) {
					didFirst = YES;
					currentLanes->push_back(*it);
					currentLane = currentLanes->back();
					newPos = currentLanes->size();
					add_line(lines, &currentLine, 1, i, newPos,(*it)->index());
					if (nParents)
						add_line(lines, &currentLine, 0, newPos, newPos,(*it)->index());
				}
				else {
					add_line(lines, &currentLine, 1, i, newPos,(*it)->index());
					delete *it;
				}
			}
			else {
				// We are not this commit.
				currentLanes->push_back(*it);
				add_line(lines, &currentLine, 1, i, currentLanes->size(),(*it)->index());
				add_line(lines, &currentLine, 0, currentLanes->size(), currentLanes->size(), (*it)->index());
			}
			// For existing columns, we always just continue straight down
			// ^^ I don't know what that means anymore :(

		}
	}
	//Add your own parents

	// If we already did the first parent, don't do so again
	if (!didFirst && nParents) {
		git_oid parentOID = [(PBGitSHA*)[parents objectAtIndex:0] oid];
		PBGitLane *newLane = new PBGitLane(&parentOID);
		currentLanes->push_back(newLane);
		newPos = currentLanes->size();
		add_line(lines, &currentLine, 0, newPos, newPos, newLane->index());
	}

	// Add all other parents

	// If we add at least one parent, we can go back a single column.
	// This boolean will tell us if that happened
	BOOL addedParent = NO;

	int parentIndex = 0;
	for (parentIndex = 1; parentIndex < nParents; ++parentIndex) {
		git_oid parentOID = [(PBGitSHA*)[parents objectAtIndex:parentIndex] oid];
		int i = 0;
		BOOL was_displayed = NO;
		LaneCollection::iterator it = currentLanes->begin();
		for (; it != currentLanes->end(); ++it) {
			i++;
			if ((*it)->isCommit(parentOID)) {
				add_line(lines, &currentLine, 0, i, newPos,(*it)->index());
				was_displayed = YES;
				break;
			}
		}
		if (was_displayed)
			continue;
		
		// Really add this parent
		addedParent = YES;
		PBGitLane *newLane = new PBGitLane(&parentOID);
		currentLanes->push_back(newLane);
		add_line(lines, &currentLine, 0, currentLanes->size(), newPos, newLane->index());
	}

	if (commit.lineInfo) {
		previous = commit.lineInfo;
		previous.position = newPos;
		previous.lines = lines;
	}
	else
		previous = [[PBGraphCellInfo alloc] initWithPosition:newPos andLines:lines];

	if (currentLine > maxLines)
		NSLog(@"Number of lines: %i vs allocated: %i", currentLine, maxLines);

	previous.nLines = currentLine;
	previous.sign = commit.sign;

	// If a parent was added, we have room to not indent.
	if (addedParent)
		previous.numColumns = currentLanes->size() - 1;
	else
		previous.numColumns = currentLanes->size();

	// Update the current lane to point to the new parent
	if (currentLane) {
		if (nParents > 0)
			currentLane->setSha([(PBGitSHA*)[parents objectAtIndex:0] oid]);
		else {
			// The current lane's commit does not have any parents
			// AKA, this is a first commit
			// Empty the entry and free the lane.
			// We empty the lane in the case of a subtree merge, where
			// multiple first commits can be present. By emptying the lane,
			// we allow room to create a nice merge line.
			std::replace(currentLanes->begin(), currentLanes->end(), currentLane, (PBGitLane *)0);
			delete currentLane;
		}
	}

	delete previousLanes;

	pl = currentLanes;
	commit.lineInfo = previous;
}

- (void) dealloc
{
	LaneCollection *lanes = (LaneCollection *)pl;
	LaneCollection::iterator it = lanes->begin();
	for (; it != lanes->end(); ++it)
		delete *it;

	delete lanes;

}
@end
