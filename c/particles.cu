#include "../h/particles.cuh"

namespace PhysPeach{
    __global__ void init_genrand_kernel(unsigned long long seed, curandState* state){
        uint i_global = blockIdx.x * blockDim.x + threadIdx.x;
        curand_init(seed, i_global,0,&state[i_global]);
    }
    
    void makeParticles(Particles* p){
        //malloc host
        p->diam = (float*)malloc(NP * sizeof(float));
        p->x = (float*)malloc(D * NP*sizeof(float));
        p->v = (float*)malloc(D * NP * sizeof(float));
    
        //malloc device
        cudaMalloc((void**)&p->diam_dev, NP * sizeof(float));
        cudaMalloc((void**)&p->x_dev, D * NP * sizeof(float));
        cudaMalloc((void**)&p->v_dev, D * NP * sizeof(float));
        cudaMalloc((void**)&p->rndState_dev, D * NP *sizeof(curandState));
        cudaMalloc((void**)&p->force_dev, D * NP*sizeof(float));
        
        //for setters and getters 
        cudaMalloc((void**)&p->getNK_dev[0], D * NP * sizeof(float));
        cudaMalloc((void**)&p->getNK_dev[1], D * NP * sizeof(float));
        cudaMalloc((void**)&p->getNU_dev[0], NP * sizeof(float));
        cudaMalloc((void**)&p->getNU_dev[1], NP * sizeof(float));
        for(uint i = 0; i< D; i++){
            cudaMalloc((void**)&p->Nvg_dev[i][0], D * NP * sizeof(float));
            cudaMalloc((void**)&p->Nvg_dev[i][1], D * NP * sizeof(float));
        }

        //set rnd seed
        init_genrand_kernel<<<NB,NT>>>((unsigned long long)genrand_int32(),p->rndState_dev);
        return;
    }
    
    void killParticles(Particles* p){
        free(p->diam);
        free(p->x);
        free(p->v);
        
        cudaFree(p->diam_dev);
        cudaFree(p->x_dev);
        cudaFree(p->v_dev);
        cudaFree(p->rndState_dev);
        cudaFree(p->force_dev);

        cudaFree(p->getNK_dev[0]);
        cudaFree(p->getNK_dev[1]);
        cudaFree(p->getNU_dev[0]);
        cudaFree(p->getNU_dev[1]);
        for(uint i = 0; i< D; i++){
            cudaFree(p->Nvg_dev[i][0]);
            cudaFree(p->Nvg_dev[i][1]);
        }
        return;
    }

    //setters and getters
    __global__ void setRndParticleStates(float l,float *diam, float *x, float *v ,curandState *rndState){
        uint i_global = blockIdx.x * blockDim.x + threadIdx.x;
        
        float atmp = a2 - a1;
        for(uint i = i_global; i < NP; i+=NB*NT){
            diam[i] = a1 + atmp * (i%2);
        }

        curandState localState = rndState[i_global];
        for(uint i = i_global; i < D * NP; i+=NB*NT){
            x[i] = l * curand_uniform(&localState);
            v[i] = 0.0;
        }
        rndState[i_global] = localState;
    }
    void scatterParticles(Particles* p, float L){
        //set positions by uniform random destribution
        setRndParticleStates<<<NB,NT>>>(L, p->diam_dev, p->x_dev, p->v_dev, p->rndState_dev);
        checkPeriodic<<<NB,NT>>>(L, p->x_dev);
        return;
    }
    __global__ void checkPeriodic(float L, float *x){
        uint n_global = blockIdx.x * blockDim.x + threadIdx.x;

        for(uint n = n_global; n < NP; n += NB*NT){
            if(x[n] > L){
                x[n] -= L;
            }
            else if (x[n] < 0){
                x[n] += L;
            }
        }
    }

    //time evolutions
    __global__ void vEvoBD(float *v, double dt, float themalFuctor, float *force, curandState *state){
        uint i_global = blockIdx.x * blockDim.x + threadIdx.x;
        for(int i = i_global; i < D * NP; i += NB*NT){
            v[i] += dt*(-v[i] + force[i] + thermalFuctor*curand_normal(&state[i]));
        }
    }
    __global__ void xEvo(float *x, double dt, float L, float *v){
        uint i_global = blockIdx.x * blockDim.x + threadIdx.x;
        for(int i = i_global; i < D * NP; i += NB*NT){
            x[i] += dt * v[i];
            //periodic
            if(x[i] > L){
                x[i] -= L;
            }
            else if(x[i] < 0){
                x[i] += L;
            }
        }
    }
    __global__ void glo_removevg(float *v, float* Nvg){
        uint i_global = blockIdx.x * blockDim.x + threadIdx.x;

        float vg_local = Nvg[0]/NP;
        for(uint i = i_global; i < NP; i += NB * NT){
            v[i] -= vg_local;
        }
    }
    inline void removevg(Particles* p){
        //summations
        uint flip = 0;
        uint l = NP;
        for(uint d = 0; d < D; d++){
            reductionSum<<<NB,NT>>>(p->Nvg_dev[d][0], &p->v_dev[d*NP], l);
        }
        l = (l + NT-1)/NT;
        while(l > 1){
            flip = !flip;
            for(uint d = 0; d < D; d++){
                reductionSum<<<NB,NT>>>(p->Nvg_dev[d][flip], p->Nvg_dev[d][!flip], l);
            }
            l = (l + NT-1)/NT;
        }
        for(uint d = 0; d < D; d++){
            glo_removevg(&p->v_dev[d*NP],p->Nvg_dev[d][flip]);
        }
        return;
    }
}