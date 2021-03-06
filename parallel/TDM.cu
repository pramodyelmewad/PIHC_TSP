#include"stdio.h"
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include"math.h"
#include <ctype.h>

/* Euclidean distance calculation */
__host__  __device__ long distD(int x,int y,int N,long*dt)
{
	int id;
	if(x>y)
	{
		x=x+y;y=x-y;x=x-y;
	}
	id=x*(N-1)+(y-1)-(x*(x+1)/2);
	return(dt[id]);
}
/*A kenel function that finds a minimal weighted neighbor using TPN mapping strategy*/
__global__ void tsp(int *rt,long cost,unsigned long long *dst_tid,long cit,long *dt,long sol)
{

	long i,j;
	long change=0;
	long id=threadIdx.x+blockIdx.x*blockDim.x;
	if(id<sol)
	{
		
		i=cit-2-floorf(((int)__dsqrt_rn(8*(sol-id-1)+1)-1)/2);
		j=id-i*(cit-1)+(i*(i+1)/2)+1;
		change=distD(rt[i],rt[j],cit,dt)+distD(rt[(i+1)%cit],rt[(j+1)%cit],cit,dt)
			-distD(rt[i],rt[(i+1)%cit],cit,dt)-distD(rt[j],rt[(j+1)%cit],cit,dt);
		cost+=change;	
		if(change < 0)
			 atomicMin(dst_tid, ((unsigned long long)cost << 32) | id);
		
	}
	
}
/* At each IHC steps, XY coordinates are arranged using next initial solution's order*/
void twoOpt(int x,int y,int *route,int city)
{
	int *tmp_r;
	int i,j;
	tmp_r=(int*)malloc(sizeof(int)*(y-x));	
	for(j=0,i=y;i>x;i--,j++)
	{
		tmp_r[j]=route[i];
	}
	for(j=0,i=x+1;i<=y;i++,j++)
	{
		route[i]=tmp_r[j];
	}
	free(tmp_r);
}

int main(int argc, char *argv[])
{
	int ch, cnt, in1;
	float in2, in3;
	FILE *f;
	float *posx, *posy;
	char str[256];  
	long dst,d,tid,x,y, cities;
        unsigned long long *d_dst_tid;
	
	int blk,thrd;
	clock_t start,end;
	long sol;
	int *r,i,j;
	f = fopen(argv[1], "r");
	if (f == NULL) {fprintf(stderr, "could not open file \n");  exit(-1);}

	ch = getc(f);  while ((ch != EOF) && (ch != '\n')) ch = getc(f);
	ch = getc(f);  while ((ch != EOF) && (ch != '\n')) ch = getc(f);
	ch = getc(f);  while ((ch != EOF) && (ch != '\n')) ch = getc(f);

	ch = getc(f);  while ((ch != EOF) && (ch != ':')) ch = getc(f);
	fscanf(f, "%s\n", str);
	cities = atoi(str);
	if (cities <= 2) {fprintf(stderr, "only %d cities\n", cities);  exit(-1);}

	sol=cities*(cities-1)/2;
	posx = (float *)malloc(sizeof(float) * cities);  if (posx == NULL) {fprintf(stderr, "cannot allocate posx\n");  exit(-1);}
	posy = (float *)malloc(sizeof(float) * cities);  if (posy == NULL) {fprintf(stderr, "cannot allocate posy\n");  exit(-1);}
	r = (int *)malloc(sizeof(int) * cities);  if (posy == NULL) {fprintf(stderr, "cannot allocate posy\n");  exit(-1);}
	
	ch = getc(f);  while ((ch != EOF) && (ch != '\n')) ch = getc(f);
	fscanf(f, "%s\n", str);
	if (strcmp(str, "NODE_COORD_SECTION") != 0) {fprintf(stderr, "wrong file format\n");  exit(-1);}

	cnt = 0;

	while (fscanf(f, "%d %f %f\n", &in1, &in2, &in3)) 
	{
		posx[cnt] = in2;
		posy[cnt] = in3;
		cnt++;
		if (cnt > cities) {fprintf(stderr, "input too long\n");  exit(-1);}
		if (cnt != in1) {fprintf(stderr, "input line mismatch: expected %d instead of %d\n", cnt, in1);  exit(-1);}
	}

	if (cnt != cities) {fprintf(stderr, "read %d instead of %d cities\n", cnt, cities);  exit(-1);}
	fscanf(f, "%s", str);
	if (strcmp(str, "EOF") != 0) {fprintf(stderr, "didn't see 'EOF' at end of file\n");  exit(-1);}
    	fflush(f);
	fclose(f);
	/*Distance matrix */
	long *dist_mat=(long*)malloc(sizeof(long)*sol);
	int k=0;	
	for (int i = 0; i < cities; ++i)
	{
		for (int j = i+1; j < cities; ++j)
		{
		dist_mat[k] = sqrtf(pow(posx[i] - posx[j], 2)
		             +powf(posy[i] - posy[j], 2));
		k++;		
		}
	}
	/* CUDA threads and block configuration */
	if(sol < 1024)
	{
		blk = 1;
		thrd = cities;
	}
	else
	{
	blk=(sol-1)/1024+1;
	thrd=1024;
	}
	/*Initial solution construction using NN approach*/
	r[0]=0;
	k=1;i=0;float min;int minj,mini,count=1,flag=0;dst=0;
	int *v=(int*)calloc(cities,sizeof(int));
	v[0]=1;
	while(count!=cities)
	{
		flag=0;
		for(j=1;j<cities;j++)
		{
			if(i!=j && !v[j])
			{
				int id;
				if(i>j)
					id=j*(cities-1)+(i-1)-(j*(j+1)/2);
				else
					id=i*(cities-1)+(j-1)-(i*(i+1)/2);
	
				min=dist_mat[id];
				minj=j;
				break;	
			}
		}

		for(j=minj+1;j<cities;j++)
		{
			 if( !v[j])
			{
				int id;
				if(i>j)
					id=j*(cities-1)+(i-1)-(j*(j+1)/2);
				else
					id=i*(cities-1)+(j-1)-(i*(i+1)/2);	
				if(min>dist_mat[id])
				{
					min=dist_mat[id];
					mini=j;
					flag=1;				
				}
			}
		}
		if(flag==0)
			i=minj;
		else
			i=mini;
		dst+=min;
		r[k++]=i;v[i]=1;
		count++;
	}
	free(v);
	j=r[cities-1];
	i=0;
	int id=i*(cities-1)+(j-1)-(i*(i+1)/2);
	dst+=dist_mat[id];
	count=1;
	start = clock();
	cudaEvent_t strt, stp;
	cudaEventCreate(&strt);
	cudaEventCreate(&stp);
 	unsigned long long dst_tid = (((long)dst+1) << 32) -1;
        unsigned long long dtid;
	int *d_r;
    	long *d_mt;
	printf("cities : %ld\ninitial cost : %ld\n",cities,dst);

	if(cudaSuccess!=cudaMalloc((void**)&d_dst_tid,sizeof(unsigned long long)))printf("\nAllocating memory for dst_tid on GPU");
    	if(cudaSuccess!=cudaMemcpy(d_dst_tid,&dst_tid,sizeof(unsigned long long),cudaMemcpyHostToDevice))printf("\ntransfer on GPU");
	if(cudaSuccess!=cudaMalloc((void**)&d_mt,sizeof(long)*sol))printf("\nAllocating memory for thread id on GPU");
    	if(cudaSuccess!=cudaMalloc((void**)&d_r,sizeof(int)*cities))printf("\nAllocating memory for thread id on GPU");
	if(cudaSuccess!=cudaMemcpy(d_mt,dist_mat,sizeof(long)*(sol),cudaMemcpyHostToDevice))printf("\ntransfer on GPU 1");
    	if(cudaSuccess!=cudaMemcpy(d_r,r,sizeof(int)*cities,cudaMemcpyHostToDevice))printf("\ntransfer on GPU 1");

	tsp<<<blk,thrd>>>(d_r,dst,d_dst_tid,cities,d_mt,sol);

	if(cudaSuccess!=cudaMemcpy(&dtid,d_dst_tid,sizeof(unsigned long long),cudaMemcpyDeviceToHost))
	printf("\nCan't transfer minimal cost back to CPU");

	float milliseconds = 0;
	cudaEventElapsedTime(&milliseconds, strt, stp);
  	d = dtid >> 32;
	printf("\nfirst cost found %ld",d);	
	while( d < dst )
	{
		dst=d;
		tid = dtid & ((1ull<<32)-1); 
		x=cities-2-floor((sqrt(8*(sol-tid-1)+1)-1)/2);
		y=tid-x*(cities-1)+(x*(x+1)/2)+1;
		twoOpt(x,y,r,cities);
		unsigned long long dst_tid = (((long)dst+1) << 32) -1;
    		if(cudaSuccess!=cudaMemcpy(d_r,r,sizeof(int)*cities,cudaMemcpyHostToDevice))printf("\ntransfer on GPU 1");
    	        if(cudaSuccess!=cudaMemcpy(d_dst_tid,&dst_tid,sizeof(unsigned long long),cudaMemcpyHostToDevice))
		printf("\ntransfer on GPU");

		tsp<<<blk,thrd>>>(d_r,dst,d_dst_tid,cities,d_mt,sol);
		if(cudaSuccess!=cudaMemcpy(&dtid,d_dst_tid,sizeof(unsigned long long),cudaMemcpyDeviceToHost))
		printf("\nCan't transfer minimal cost back to CPU");
	  	d = dtid >> 32;
		count++;
	}
	printf("\nMinimal Distance : %ld\n",d);

	printf("\nnumber of time climbed %d\n",count);
	end = clock();
	double t=((double) (end - start)) / CLOCKS_PER_SEC;
	printf("\ntime : %f\n",t);

	cudaFree(d_r);
	cudaFree(d_mt);
	cudaFree(d_dst_tid);
	free(posx);
	free(posy);
	free(r);
	return 0;
}
