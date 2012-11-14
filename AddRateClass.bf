//VERBOSITY_LEVEL = 0;

// Testing with nucCF passed in
function addRate2Branch(lfID, nucCF, branchName, defaultModel, modelList)
{
    ExecuteCommands ("GetString(lfInfoAA, " + lfID + ", -1)");
    lfTree = lfInfoAA["Trees"];
    lfTreeID = lfTree[0];
    ExecuteCommands ("orig_tree_string = Format(" + lfTreeID + ",1,1)");

    lfdsf = lfInfoAA["Datafilters"];
    lfdsfID = lfdsf[0];
    ExecuteCommands ("HarvestFrequencies (lfnuc3," + lfdsfID + ", 3, 1, 1)");
    //lfnucCF = CF3x4 (lfnuc3, GeneticCodeExclusions); // XXX BREAKS HERE
    lfnucCF = nucCF;

    currentParams = {};
    paramProportions = {};

    numOmegas = 1;
    nextOmega = 1;
    // Check and store previous Omegas
    openOmegaFound = 0;
    while (openOmegaFound != 1)
    {
        // Grab the previous omega. If it exists omegaInfo will be a matrix of length three.
        // Otherwise it will be a matrix of length one (I think).
        ExecuteCommands("GetInformation(omegaInfo, " + lfTreeID + "." + branchName + ".omega" + numOmegas + ")");
        // Check to see if this previous omega exists.
        if (Columns(omegaInfo) == 3)
        {
            fprintf(stdout, "\nomega found!\n");
            // Alright, it does. Now lets get information regarding its proportion (remember,
            // the number of proportions is (the number of rate classes) - 1.
            prevOmega = numOmegas - 1;
            if (prevOmega >= 1)
            {
                ExecuteCommands("GetInformation(PauxInfo, " + lfTreeID + "." + branchName + ".Paux" + prevOmega + ")");
                // Save the proportion (part)
                paramProportions[prevOmega] = PauxInfo[0];
            }
            // Save the rate class rate
            currentParams[numOmegas] = omegaInfo[0];
            // Iterate the future rate class identity counter
            nextOmega = nextOmega + 1;
        }
        else
        {
            openOmegaFound = 1;
        }
        numOmegas = numOmegas + 1;
    }
    // So I guess if nextOmega = 1 then the original n/ns rate needs to
    // become omega1 and there needs to be an additional omega2 rate class.
    // This will of course mean nextOmega = 2, and this need to make sense
    // going forward
    if (nextOmega == 1)
    {
        currentParams[1] = 10;
        currentParams[2] = 1;
        paramProportions[1] = .9;
        srate = Eval (lfTreeID + "." + branchName + ".syn");
        nsrate = Eval (lfTreeID + "." + branchName + ".nonsyn");
        if (srate > 0)
        {
            currentParams[0] = Min (10, nsrate/srate);
        }
        nextOmega = 2;
    }
    else
    {
        newProportion = paramProportions[nextOmega - 2] * .1;
        paramProportions[nextOmega - 2] = 1 - newProportion;
        paramProportions[nextOmega - 1] = newProportion;
        currentParams[nextOmega] = .9;
    }

    // Build a model matrix for each rate class to be used (in proportion)
    // in the LF.
    for (matrixI = 1; matrixI <= nextOmega; matrixI = matrixI + 1)
    {
        ExecuteCommands("PopulateModelMatrix(\"MGMatrix" + matrixI + "\", lfnucCF, \"t\", \"omega" + matrixI + "\", \"\");");
    }

    lfModel = lfInfoAA["Models"];
    lfModelID = lfModel[0];

    lfbaseFreqs = lfInfoAA["Base frequencies"];
    lfbaseFreqsID = lfbaseFreqs[0];

    matrixString = "";
    for (paramI = 1; paramI <= nextOmega; paramI = paramI + 1)
    {
        if (paramI > 1)
        {
            matrixString = matrixString + "+";
        }
        // We need the matrix from the rate class
        matrixString = matrixString + "Exp(MGMatrix" + paramI + ")";
        // However we don't store the proportion for the last rate class (DOF = # rate classes - 1)
        if (paramI != nextOmega)
        {
            matrixString = matrixString + "*Paux" + paramI;
        }
        // As we don't store the proportion for the last rate class, we need to be able to determine
        // that proportion from the other proportions. This relationship is used below:
        for (prevParamI = paramI - 1; prevParamI > 0; prevParamI = prevParamI - 1)
        {
            matrixString = matrixString + "*(1-Paux" + prevParamI + ")";
        }
    }
    ExecuteCommands ("Model BSREL = (matrixString, " + lfbaseFreqsID + ", EXPLICIT_FORM_MATRIX_EXPONENTIAL);");



    ExecuteCommands ("Model BSREL" + nextOmega + " = (matrixString, " + lfbaseFreqsID + ", EXPLICIT_FORM_MATRIX_EXPONENTIAL);");

    modelList[nextOmega] = "BSREL" + nextOmega;




    new_tree_string = orig_tree_string;
    fprintf(stdout, new_tree_string);
    fprintf(stdout, "\n");
    //ExecuteCommands ("UseModel(" + lfModelID + ")");
    ExecuteCommands ("UseModel(" + defaultModel + ")");
    fprintf(stdout, new_tree_string);
    fprintf(stdout, "\n");

    new_tree_string = new_tree_string^{{branchName, branchName + "{BSREL}"}};
    fprintf(stdout, new_tree_string);
    fprintf(stdout, "\n");

    ExecuteCommands ("Tree `lfTreeID` = `new_tree_string`");
    ExecuteCommands ("LikelihoodFunction `lfID` = (`lfdsfID`, `lfTreeID`);");

    for (omegaI = 1; omegaI <= nextOmega; omegaI = omegaI + 1)
    {
        ExecuteCommands(lfTreeID + "." + branchName + ".omega" + omegaI + " = " + currentParams[omegaI] + ";");
        if (omegaI != nextOmega)
        {
            ExecuteCommands(lfTreeID + "." + branchName + ".Paux" + omegaI + " = " + paramProportions[omegaI] + ";");
            ExecuteCommands(lfTreeID + "." + branchName + ".Paux" + omegaI + " :< 1;");
        }
    }

/*
    if (nextOmega == 1)
    {
        ExecuteCommands(lfTreeID + "." + branchName + ".omega" + nextOmega + " = " + initOmega + ";"); // XXX fix value
        ExecuteCommands(lfTreeID + "." + branchName + ".Paux" + nextOmega + " = " + initProportion + ";"); // XXX fix propotion
        ExecuteCommands(lfTreeID + "." + branchName + ".Paux" + nextOmega + " :< 1;"); // XXX fix propotion
        nextOmega = nextOmega + 1;

        ExecuteCommands(lfTreeID + "." + branchName + ".omega" + nextOmega + " = .9;"); // XXX fix value
        ExecuteCommands(lfTreeID + "." + branchName + ".Paux" + nextOmega + " = " + newProportion + ";"); // XXX fix propotion
        ExecuteCommands(lfTreeID + "." + branchName + ".Paux" + nextOmega + " :< 1;"); // XXX fix propotion
    }
    else
    {
        ExecuteCommands(lfTreeID + "." + branchName + ".omega" + nextOmega + " = .9;"); // XXX fix value
        ExecuteCommands(lfTreeID + "." + branchName + ".Paux" + nextOmega + " = " + newProportion + ";"); // XXX fix propotion
        ExecuteCommands(lfTreeID + "." + branchName + ".Paux" + nextOmega + " :< 1;"); // XXX fix propotion
    }
*/

    return 0;
}

return 0;
