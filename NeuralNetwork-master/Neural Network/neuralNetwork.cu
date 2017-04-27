//standard includes
#include <iostream>
#include <vector>
#include <fstream>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <algorithm>

#include <cuda.h>
#include <cuda_runtime.h>
#include <driver_functions.h>
#include <curand.h>
#include <curand_kernel.h>

//include definition file
#include "neuralNetwork.h"

using namespace std;

__global__ void
weights1_kernel(double *device_output, int num_inputs, int num_hidden) {
	int index = blockIdx.x * blockDim.x + threadIdx.x;

	curandState state;
	unsigned int seed = index;
	curand_init(seed, 0, 0, &state);
	float rand = curand_uniform(&state);
    
    int i = index/num_hidden;
    int j = index - i*num_hidden;
    if (index < num_inputs*num_hidden) {
    	// device_output[i][j] = ( (( (double)(rand%1000)+1)/1000)/10 - 0.05);
    	device_output[i*num_hidden + j] = ( (double)(rand)/10 - 0.05);
    }
}

__global__ void
weights2_kernel(double *device_output, int num_hidden, int num_outputs) {
	int index = blockIdx.x * blockDim.x + threadIdx.x;

	curandState state;
	unsigned int seed = index;
	curand_init(seed, 0, 0, &state);
	float rand = curand_uniform(&state);

    int i = index/num_outputs;
    int j = index - i*num_outputs;
    if (index < num_outputs*num_hidden) {
    	// device_output[i][j] = ( (( (double)(rand%1000)+1)/1000)/10 - 0.05);
    	device_output[i*num_outputs + j]  = ( (double)(rand)/10 - 0.05);
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
	for ( int i=0; i <= nInput; i++ ) 
	{
		wInputHidden[i] = new (double[nHidden]);
		for ( int j=0; j < nHidden; j++ ) wInputHidden[i][j] = 0;		
	}

	wHiddenOutput = new( double*[nHidden + 1] );
	for ( int i=0; i <= nHidden; i++ ) 
	{
		wHiddenOutput[i] = new (double[nOutput]);			
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
	printf("%f\n", wInputHidden[0][0]);
	int threadsPerBlock = 256;
    int blocks1 = ((nInput+1)*nHidden + threadsPerBlock - 1) / threadsPerBlock;
    int blocks2 = (nOutput*(nHidden+1) + threadsPerBlock - 1) / threadsPerBlock;

	double *device_output1;
    cudaMalloc((void **)&device_output1, sizeof(double) * (nInput+1)*nHidden);
    printf("HERE\n");
	weights1_kernel<<<blocks1, threadsPerBlock>>>(device_output1, nInput+1, nHidden);
	printf("WHOA\n");

	double *device_output2;
	cudaMalloc((void **)&device_output2, sizeof(double) * (nHidden+1)*nOutput);
	printf("AGAIN\n");
	weights2_kernel<<<blocks2, threadsPerBlock>>>(device_output2, nHidden+1, nOutput);
	printf("WHOA AGAIN\n");

	cudaThreadSynchronize();

	printf("ABOUT TO COPY\n");
	//for (int i =0; i<=nInput; i++) {
		//cudaMemcpy(&wInputHidden[i], &device_output1[i*nHidden], sizeof(double)*nHidden, cudaMemcpyDeviceToHost);
		//printf("%f\n", wInputHidden[i][0]);
	cudaMemcpy(&wInputHidden, &device_output1, sizeof(double)*nHidden*(nInput+1), cudaMemcpyDeviceToHost);
	//}
	printf("DONE FIRST\n");

	cudaFree(device_output1);

	printf("ABOUT TO COPY 2\n");
	//for (int i =0; i<=nHidden; i++) {
		//cudaMemcpy(&wHiddenOutput[i], &device_output2[i*nOutput], sizeof(double)*nOutput, cudaMemcpyDeviceToHost);
	cudaMemcpy(&wHiddenOutput, &device_output2, sizeof(double)*(nHidden+1)*nOutput, cudaMemcpyDeviceToHost);
	//}
	printf("DONE SECOND\n");

	cudaFree(device_output2);

	// //set weights between input and hidden 		
	// //--------------------------------------------------------------------------------------------------------
	// for(int i = 0; i <= nInput; i++)
	// {		
	// 	for(int j = 0; j < nHidden; j++) 
	// 	{
	// 		//set weights to random values
	// 		wInputHidden[i][j] = ( (( (double)(rand()%1000)+1)/1000)/10 - 0.05);
	// 	}
	// }
	
	// //set weights between input and hidden
	// //--------------------------------------------------------------------------------------------------------
	// for(int i = 0; i <= nHidden; i++)
	// {		
	// 	for(int j = 0; j < nOutput; j++) 
	// 	{
	// 		//set weights to random values
	// 		wHiddenOutput[i][j] = ( (( (double)(rand()%1000)+1)/1000)/10 - 0.05);
	// 	}
	// }
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
	
	//Calculate Hidden Layer values - include bias neuron
	//--------------------------------------------------------------------------------------------------------
	for(int j=0; j < nHidden; j++)
	{
		//clear value
		hiddenNeurons[j] = 0;				
		
		//get weighted sum of pattern and bias neuron
		for( int i=0; i <= nInput; i++ ) {
			hiddenNeurons[j] += inputNeurons[i] * wInputHidden[i][j];
		}
		
		//set to result of sigmoid
		hiddenNeurons[j] = activationFunction( hiddenNeurons[j] );			
	}
	
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

