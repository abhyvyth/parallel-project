//standard includes
#include <iostream>
#include <vector>
#include <fstream>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <algorithm>
#include <omp.h>

#include <cuda.h>
#include <cuda_runtime.h>
#include <driver_functions.h>
#include <curand.h>
#include <curand_kernel.h>

#include "CycleTimer.h"

//include definition file
#include "neuralNetwork.h"

using namespace std;



__global__ void
forward_prop_w1(double *device_output, double *input, double *weights, int num_inputs, int num_hidden) {
	int index = blockIdx.x * blockDim.x + threadIdx.x;
	// printf("ind %d\n", index);

	// int row = index/num_inputs;
	// int col = index%num_hidden;


	double temp = 0.0;

	if (index<num_hidden) {
		for (int i= 0; i<num_inputs; i++) {
			temp += input[i] * weights[i*num_hidden + index];

		}
		// row is always 0 and col is [0, 30]
		device_output[index] = 1/(1+exp(-1*temp));
		//printf("temp: %f output %f\n", temp, device_output[index] );
	}

	
}


/*******************************************************************
* Constructor
********************************************************************/
neuralNetwork::neuralNetwork(int nI, int nH, int nO) : nInput(nI), nHidden(nH), nOutput(nO)
{				
	//create neuron lists
	//--------------------------------------------------------------------------------------------------------
	inputNeurons = new( double[nInput + 1] );
	for ( int i=0; i < nInput; i++ ) inputNeurons[i] = 0;

	//create input bias neuron
	inputNeurons[nInput] = -1;

	hiddenNeurons = new( double[nHidden + 1] );
	for ( int i=0; i < nHidden; i++ ) hiddenNeurons[i] = 0;

	//create hidden bias neuron
	hiddenNeurons[nHidden] = -1;

	outputNeurons = new( double[nOutput] );
	for ( int i=0; i < nOutput; i++ ) outputNeurons[i] = 0;

	//create weight lists (include bias neuron weights)
	//--------------------------------------------------------------------------------------------------------
	wInputHidden = new( double*[nInput + 1] );
	wInputHidden[0] = new (double[(nInput + 1)*nHidden]);
	for ( int i=1; i <= nInput; i++ ) {
		wInputHidden[i] = wInputHidden[i-1] + nHidden;
	}
	for ( int i=0; i <= nInput; i++ ) 
	{
		for ( int j=0; j < nHidden; j++ ) wInputHidden[i][j] = 0;		
	}

	wHiddenOutput = new( double*[nHidden + 1] );
	wHiddenOutput[0] = new (double[(nHidden + 1)*nOutput]);
	for ( int i=1; i <= nHidden; i++ ) {
		wHiddenOutput[i] = wHiddenOutput[i-1] + nOutput;
	}
	for ( int i=0; i <= nHidden; i++ ) 
	{
		for ( int j=0; j < nOutput; j++ ) wHiddenOutput[i][j] = 0;		
	}	
	
	//initialize weights
	//--------------------------------------------------------------------------------------------------------
	initializeWeights();		
}

/*******************************************************************
* Destructor
********************************************************************/
neuralNetwork::~neuralNetwork()
{
	//delete neurons
	delete[] inputNeurons;
	delete[] hiddenNeurons;
	delete[] outputNeurons;

	//delete weight storage
	for (int i=0; i <= nInput; i++) delete[] wInputHidden[i];
	delete[] wInputHidden;

	for (int j=0; j <= nHidden; j++) delete[] wHiddenOutput[j];
	delete[] wHiddenOutput;

	cudaFree(device_output1);
	cudaFree(input);
	cudaFree(w1);
}

/*******************************************************************
* Save Neuron Weights
********************************************************************/
bool neuralNetwork::saveWeights(char* filename)
{
	//open file for reading
	fstream outputFile;
	outputFile.open(filename, ios::out);

	if ( outputFile.is_open() )
	{
		outputFile.precision(50);		

		//output weights
		for ( int i=0; i <= nInput; i++ ) 
		{
			for ( int j=0; j < nHidden; j++ ) 
			{
				outputFile << wInputHidden[i][j] << ",";				
			}
		}
		
		for ( int i=0; i <= nHidden; i++ ) 
		{		
			for ( int j=0; j < nOutput; j++ ) 
			{
				outputFile << wHiddenOutput[i][j];					
				if ( i * nOutput + j + 1 != (nHidden + 1) * nOutput ) outputFile << ",";
			}
		}

		//print success
		cout << endl << "Neuron weights saved to '" << filename << "'" << endl;

		//close file
		outputFile.close();
		
		return true;
	}
	else 
	{
		cout << endl << "Error - Weight output file '" << filename << "' could not be created: " << endl;
		return false;
	}
}

/*******************************************************************
* Return the NN accuracy on the set
********************************************************************/
double neuralNetwork::getSetAccuracy( std::vector<dataEntry*>& set )
{
	double incorrectResults = 0;
		
	//for every training input array
	for ( int tp = 0; tp < (int) set.size(); tp++)
	{						
		//feed inputs through network and backpropagate errors
		feedForward( set[tp]->pattern );

		int predicted = distance(outputNeurons, max_element(outputNeurons, outputNeurons + nOutput));
		int expected = distance(set[tp]->target, max_element(set[tp]->target, set[tp]->target + nOutput));
		
		if (predicted != expected) incorrectResults++;	
		
	}//end for
	
	//calculate error and return as percentage
	return 100 - (incorrectResults/set.size() * 100);
}

/*******************************************************************
* Initialize Neuron Weights
********************************************************************/
void neuralNetwork::initializeWeights()
{
	double startTime = CycleTimer::currentSeconds();

	cudaMalloc(&device_output1, sizeof(double) * nHidden);
    
    cudaMalloc(&input, sizeof(double) * (nInput+1));

    cudaMalloc(&w1, sizeof(double) * (nInput+1)*nHidden);

	//set weights between input and hidden 		
	//--------------------------------------------------------------------------------------------------------
	for(int i = 0; i <= nInput; i++)
	{		
		for(int j = 0; j < nHidden; j++) 
		{
			//set weights to random values
			wInputHidden[i][j] = ( (( (double)(rand()%1000)+1)/1000)/10 - 0.05);
		}
	}
	
	//set weights between input and hidden
	//--------------------------------------------------------------------------------------------------------
	for(int i = 0; i <= nHidden; i++)
	{		
		for(int j = 0; j < nOutput; j++) 
		{
			//set weights to random values
			wHiddenOutput[i][j] = ( (( (double)(rand()%1000)+1)/1000)/10 - 0.05);
		}
	}
	double endTime = CycleTimer::currentSeconds();
    double overallDuration = endTime - startTime;

    printf("Time Taken Seq:%f\n", overallDuration);
}
/*******************************************************************
* Activation Function
********************************************************************/
inline double neuralNetwork::activationFunction( double x )
{
	//sigmoid function
	return 1/(1+exp(-x));
}	

/*******************************************************************
* Feed Forward Operation
********************************************************************/
void neuralNetwork::feedForward(double* pattern)
{
	//set input neurons to input values
	for(int i = 0; i < nInput; i++) {
		inputNeurons[i] = pattern[i];
	}

	
    cudaMemcpy(input, inputNeurons, sizeof(double) * (nInput+1), cudaMemcpyHostToDevice);
    
    cudaMemcpy(w1, wInputHidden[0], (nInput+1)*nHidden*sizeof(double), cudaMemcpyHostToDevice);

	forward_prop_w1<<<1, 30>>>(device_output1, input, w1, nInput+1, nHidden);

	cudaDeviceSynchronize();

	cudaMemcpy(hiddenNeurons, device_output1, nHidden*sizeof(double), cudaMemcpyDeviceToHost);

	// for (int j = 0 ; j < nHidden ; j++) {
	// 	cout << " Hidden " << hiddenNeurons[j] << endl;
	// }

	
	//Calculate Hidden Layer values - include bias neuron
	//--------------------------------------------------------------------------------------------------------
	// for(int j=0; j < nHidden; j++)
	// {
	// 	//clear value
	// 	hiddenNeurons[j] = 0;				
		
	// 	//get weighted sum of pattern and bias neuron
	// 	for( int i=0; i <= nInput; i++ ) {
	// 		hiddenNeurons[j] += inputNeurons[i] * wInputHidden[i][j];
	// 	}
	// 	// cout << "temp: " << hiddenNeurons[j] << endl;
	// 	//set to result of sigmoid
	// 	hiddenNeurons[j] = activationFunction( hiddenNeurons[j] );			
	// 	// cout << "output: " << hiddenNeurons[j] << endl;
	// }
	
	//Calculating Output Layer values - include bias neuron
	//--------------------------------------------------------------------------------------------------------
	for(int k=0; k < nOutput; k++)
	{
		//clear value
		outputNeurons[k] = 0;				
		
		//get weighted sum of pattern and bias neuron
		for( int j=0; j <= nHidden; j++ ) outputNeurons[k] += hiddenNeurons[j] * wHiddenOutput[j][k];
		
		//set to result of sigmoid
		outputNeurons[k] = activationFunction( outputNeurons[k] );
	}
}

void neuralNetwork::printCudaInfo()
{
    // for fun, just print out some stats on the machine

    int deviceCount = 0;
    cudaError_t err = cudaGetDeviceCount(&deviceCount);

    printf("---------------------------------------------------------\n");
    printf("Found %d CUDA devices\n", deviceCount);

    for (int i=0; i<deviceCount; i++)
    {
        cudaDeviceProp deviceProps;
        cudaGetDeviceProperties(&deviceProps, i);
        printf("Device %d: %s\n", i, deviceProps.name);
        printf("   SMs:        %d\n", deviceProps.multiProcessorCount);
        printf("   Global mem: %.0f MB\n",
               static_cast<float>(deviceProps.totalGlobalMem) / (1024 * 1024));
        printf("   CUDA Cap:   %d.%d\n", deviceProps.major, deviceProps.minor);
    }
    printf("---------------------------------------------------------\n"); 
}

