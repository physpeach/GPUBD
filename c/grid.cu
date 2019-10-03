#include "../h/grid.cuh"

namespace PhysPeach{
    void makeGrid(Grid* grid, float L){
        ////define M ~ L/Rcell: Rcell ~ 5a
        grid->M = (uint)(L/(4.8*a0));
        ////for small system
        if(grid->M < 3){
            grid->M = 3;
        }
        grid->rc = L/(float)grid->M;
        uint M2 = grid->M * grid->M;
        grid->EpM = (uint)(1.5 * (float)NP /(float)M2); //EpM ~ NP/M^D

        cudaMalloc((void**)&grid->cell_dev, M2 * grid->EpM * sizeof(uint));

        //for parallel interactions
        IT = grid->EpM * NG * NG;
        uint M_NG = grid->M/NG + 0.9;
        cudaMalloc((void**)&grid->refCell_dev, M_NG * M_NG * sizeof(uint));
        makeCellPattern2D(grid);

        return;
    }
    void killGrid(Grid* grid){
        cudaFree(grid->refCell_dev);
        cudaFree(grid->cell_dev);
    }
    void makeCellPattern2D(Grid* grid){
        uint M_NG = grid->M/NG + 0.9;
        uint pattern[M_NG*M_NG];

        uint foo = 0;
        uint hoge = 0;
        uint hhoge = 0;
        for(uint m_NG2 = 0; m_NG2 < M_NG*M_NG; m_NG2++){
            hhoge = m_NG2/M_NG;
            hoge = m_NG2 - hhoge * M_NG;
            if(!hoge){
                foo = NG * hhoge * grid->M;
            }
            pattern[m_NG2] = foo;
            foo += NG;
        }
        cudaMemcpy(grid->refCell_dev, pattern, M_NG * M_NG * sizeof(uint), cudaMemcpyHostToDevice);
        return;
    }
}